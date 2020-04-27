class Events < Application
  base "/api/staff/v1/events"

  def index
    args = CalendarPeriod.new(params)
    calendars = matching_calendar_ids
    render(json: [] of Nil) unless calendars.size > 0

    user = user_token.user.email
    calendar = calendar_for(user)

    # Grab events in parallel
    results = Promise.all(calendars.map { |calendar_id, system|
      Promise.defer {
        calendar.events(
          calendar_id,
          args.period_start.not_nil!,
          args.period_end.not_nil!
        ).items.map { |event| {calendar_id, system, event} }
      }
    }).get.flatten

    # Grab any existing eventmeta data
    metadatas = {} of String => EventMetadata
    metadata_ids = results.map { |(calendar_id, system, event)|
      system.nil? ? nil : "meta-#{system.id}-#{event.id}"
    }.compact
    EventMetadata.get_all(metadata_ids).each { |meta| metadatas[meta.event_id.not_nil!] = meta }

    # return array of standardised events
    render json: results.map { |(calendar_id, system, event)|
      standard_event(calendar_id, system, event, metadatas[event.id]?)
    }
  end

  def show
    event_id = route_params["id"]
    if user_cal = query_params["calendar"]?
      # Need to confirm the user can access this calendar
      found = get_user_calendars.reject { |cal| cal[:id] != user_cal }.first?
      head(:not_found) unless found

      # Grab the event details
      event = get_event(event_id, user_cal)
      head(:not_found) unless event

      render json: standard_event(user_cal, nil, event, nil)
    elsif system_id = query_params["system_id"]?
      # Need to grab the calendar associated with this system
      system = get_placeos_client.systems.fetch(system_id)
      # TODO:: return 404 if system not found
      cal_id = system.email
      head(:not_found) unless cal_id

      event = get_event(event_id, cal_id)
      head(:not_found) unless event

      metadata = EventMetadata.find("meta-#{system_id}-#{event_id}")
      render json: standard_event(cal_id, system, event, metadata)
    end

    head :bad_request
  end

  def destroy
    event_id = route_params["id"]
    notify_guests = query_params["notify"] != "false"
    notify_option = notify_guests ? Google::UpdateGuests::All : Google::UpdateGuests::None

    if user_cal = query_params["calendar"]?
      # Need to confirm the user can access this calendar
      found = get_user_calendars.reject { |cal| cal[:id] != user_cal }.first?
      head(:not_found) unless found

      # Grab the event details
      calendar = calendar_for(user_token.user.email)
      calendar.delete(event_id, user_cal, notify_option)

      head :accepted
    elsif system_id = query_params["system_id"]?
      # Need to grab the calendar associated with this system
      system = get_placeos_client.systems.fetch(system_id)
      # TODO:: return 404 if system not found
      cal_id = system.email
      head(:not_found) unless cal_id

      EventMetadata.find("meta-#{system_id}-#{event_id}").try &.destroy
      calendar = calendar_for # admin when no user passed
      calendar.delete(event_id, cal_id, notify_option)

      head :accepted
    end

    head :bad_request
  end

  get("/:id/guests", :guest_list) do
    event_id = route_params["id"]
    render(json: [] of Nil) if query_params["calendar"]?
    system_id = query_params["system_id"]?
    head :bad_request unless system_id

    # Grab meeting metadata if it exists
    metadata = EventMetadata.find("meta-#{system_id}-#{event_id}")
    render(json: [] of Nil) unless metadata

    # Find anyone who is attending
    visitors = metadata.attendees.to_a
    render(json: [] of Nil) if visitors.empty?

    # Grab the guest profiles if they exist
    guests = {} of String => Guest
    guest_ids = visitors.map { |visitor| "guest-#{visitor.email}" }
    Guest.get_all(guest_ids).each { |guest| guests[guest.email.not_nil!] = guest }

    # Merge the visitor data with guest profiles
    visitors = visitors.map do |visitor|
      attending_guest(visitor, guests[visitor.email]?)
    end

    response.headers["Content-Type"] = "application/json"
    render(text: "[#{visitors.join(',')}]")
  end

  post("/:id/guests/:guest_id/checkin", :guest_checkin) do
    event_id = route_params["id"]
    guest_email = route_params["guest_id"]
    checkin = (query_params["state"]? || "true") == "true"

    attendee = Attendee.where(email: guest_email, event_id: event_id).first
    attendee.checked_in = checkin
    attendee.save!

    response.headers["Content-Type"] = "application/json"
    render text: attending_guest(attendee, attendee.guest_details)
  end

  def attending_guest(visitor, guest)
    if guest
      # Combine these:
      guest_json = guest.to_json[0..-2]
      visitor_json = {
        checked_in:     visitor.checked_in,
        visit_expected: visitor.visit_expected,
      }.to_json[1..-1]
      "#{guest_json},#{visitor_json}"
    else
      {
        email:          visitor.email,
        checked_in:     visitor.checked_in,
        visit_expected: visitor.visit_expected,
      }.to_json
    end
  end

  def get_event(event_id, cal_id)
    calendar = calendar_for(user_token.user.email)
    calendar.event(event_id, cal_id)
  end

  # So we don't have to allocate array objects
  NOP_ATTEND   = [] of Attendee
  NOP_G_ATTEND = [] of ::Google::Calendar::Attendee

  def standard_event(calendar_id, system, event, metadata)
    visitors = {} of String => Attendee
    (metadata.try(&.attendees) || NOP_ATTEND).each { |vis| visitors[vis.email.not_nil!] = vis }

    # Grab the list of external visitors
    attendees = (event.attendees || NOP_G_ATTEND).map do |attendee|
      email = attendee.email
      if visitor = visitors[email]
        {
          name:            attendee.displayName || email,
          email:           email,
          response_status: attendee.responseStatus,
          checked_in:      visitor.checked_in,
          visit_expected:  visitor.visit_expected,
        }
      else
        {
          name:            attendee.displayName || email,
          email:           email,
          response_status: attendee.responseStatus,
          organizer:       attendee.organizer,
        }
      end
    end

    event_start = (event.start.dateTime || event.start.date).not_nil!.to_unix
    event_end = event.end.try { |time| (time.dateTime || time.date).try &.to_unix }

    # TODO:: recurring events
    # TODO:: location

    {
      id:             event.id,
      status:         event.status,
      calendar:       calendar_id,
      title:          event.summary,
      body:           event.description,
      host:           event.organizer,
      creator:        event.creator,
      private:        event.visibility.in?({"private", "confidential"}),
      event_start:    event_start,
      event_end:      event_end,
      timezone:       event.start.timeZone,
      all_day:        !!event.start.date,
      attendees:      attendees,
      system:         system,
      extension_data: (metadata.try &.extension_data) || {} of Nil => Nil,
    }
  end
end
