class Events < Application
  base "/api/staff/v1/events"

  def index
    period_start = Time.unix(query_params["period_start"].to_i64)
    period_end = Time.unix(query_params["period_end"].to_i64)
    calendars = matching_calendar_ids
    render(json: [] of Nil) unless calendars.size > 0

    include_cancelled = query_params["include_cancelled"]? == "true"
    user = user_token.user.email
    calendar = calendar_for(user)

    # Grab events in parallel
    results = Promise.all(calendars.map { |calendar_id, system|
      Promise.defer {
        calendar.events(
          calendar_id,
          period_start,
          period_end,
          showDeleted: include_cancelled
        ).items.map { |event| {calendar_id, system, event} }
      }
    }).get.flatten

    # Grab any existing eventmeta data
    metadatas = {} of String => EventMetadata
    metadata_ids = results.map { |(calendar_id, system, event)|
      system.nil? ? nil : "#{system.id}-#{event.id}"
    }.compact

    # Don't perform the query if there are no calendar entries
    if !metadata_ids.empty?
      EventMetadata.where(:id, :in, metadata_ids).each { |meta| metadatas[meta.event_id] = meta }
    end

    # return array of standardised events
    render json: results.map { |(calendar_id, system, event)|
      standard_event(calendar_id, system, event, metadatas[event.id]?)
    }
  end

  class CreateCalEvent
    include JSON::Serializable

    # This is the resource calendar, it will be moved to one of the attendees
    property system_id : String?
    property title : String # summary
    property body : String? # description
    property location : String?
    property status : String?

    # creator == current user
    property host : String?  # organizer
    property private : Bool? # visibility

    property event_start : Int64
    property event_end : Int64
    property timezone : String?

    property attendees : Array(NamedTuple(
      name: String?,
      email: String,
      visit_expected: Bool?))?

    property extension_data : JSON::Any?
  end

  def create
    # Create event
    event = CreateCalEvent.from_json(request.body.as(IO))
    user = user_token.user.email
    host = event.host || user
    calendar = calendar_for(user)

    attendees = event.attendees.try(&.map { |a| a[:email] }) || [] of String
    placeos_client = get_placeos_client

    system_id = event.system_id
    if system_id
      system = placeos_client.systems.fetch(system_id)
      attendees << system.email.not_nil!
    end

    attendees.uniq!

    zone = if tz = event.timezone
             Time::Location.load(tz)
           else
             get_timezone
           end
    event_start = Time.unix(event.event_start).in zone
    event_end = Time.unix(event.event_end).in zone

    gevent = calendar.create(
      event_start: event_start,
      event_end: event_end,
      calendar_id: host,
      attendees: attendees,
      visibility: event.private ? Google::Visibility::Private : Google::Visibility::Default,
      location: event.location,
      summary: event.title,
      description: event.body
    )

    # Update PlaceOS with an signal "/staff/event/changed"
    if system
      sys = system.not_nil!
      # Grab the list of externals that might be attending
      attending = event.attendees.try(&.select { |attendee|
        attendee[:visit_expected]
      })

      spawn do
        placeos_client.root.signal("staff/event/changed", {
          action:    :create,
          system_id: event.system_id,
          event_id:  gevent.id,
          host:      host,
          resource:  sys.email,
        })
      end

      # Save custom data
      ext_data = event.extension_data
      if ext_data || (attending && !attending.empty?)
        meta = EventMetadata.new
        meta.system_id = sys.id.not_nil!
        meta.event_id = gevent.id
        meta.event_start = event_start.to_unix
        meta.event_end = event_end.to_unix
        meta.resource_calendar = sys.email.not_nil!
        meta.host_email = host
        meta.extension_data = ext_data
        meta.save!

        Log.info { "saving extension data for event #{gevent.id} in #{sys.id}" }

        if attending
          # Create guests
          attending.each do |attendee|
            email = attendee[:email].strip.downcase
            guest = Guest.find(email) || Guest.new
            guest.email = email
            guest.name ||= attendee[:name]
            guest.save!
          end

          # Create attendees
          attending.each do |attendee|
            email = attendee[:email].strip.downcase
            attend = Attendee.new
            attend.event_id = meta.id.not_nil!
            attend.guest_id = email
            attend.visit_expected = true
            attend.save!
          end
        end

        render json: standard_event(sys.email, sys, gevent, meta)
      end

      Log.info { "no extension data for event #{gevent.id} in #{sys.id}, #{ext_data}" }

      render json: standard_event(sys.email, sys, gevent, nil)
    end

    Log.info { "no system provided for event #{gevent.id}" }

    render json: standard_event(host, nil, gevent, nil)
  end

  class UpdateCalEvent
    include JSON::Serializable

    # This is the resource calendar, it will be moved to one of the attendees
    property system_id : String?
    property title : String? # summary
    property body : String?  # description
    property location : String?
    property status : String?

    # creator == current user
    property host : String?  # organizer
    property private : Bool? # visibility

    property event_start : Int64?
    property event_end : Int64?
    property timezone : String?

    property attendees : Array(NamedTuple(
      name: String?,
      email: String,
      visit_expected: Bool?))?

    property extension_data : JSON::Any?
  end

  def update
    event_id = route_params["id"]
    changes = UpdateCalEvent.from_json(request.body.as(IO))

    placeos_client = get_placeos_client

    cal_id = if user_cal = query_params["calendar"]?
               found = get_user_calendars.reject { |cal| cal[:id] != user_cal }.first?
               head(:not_found) unless found
               user_cal
             elsif system_id = (query_params["system_id"]? || changes.system_id)
               system = placeos_client.systems.fetch(system_id)
               # TODO:: return 404 if system not found
               sys_cal = system.email
               head(:not_found) unless sys_cal
               sys_cal
             else
               head :bad_request
             end
    event = get_event(event_id, cal_id)
    head(:not_found) unless event

    # User details
    user = user_token.user.email
    host = event.organizer.try &.email || user

    # TODO:: check permisions as may be able to edit on behalf of the user

    existing_attendees = event.attendees.try(&.map { |a| a.email }) || [] of String
    head(:forbidden) unless user == host || user.in?(existing_attendees)
    calendar = calendar_for(host)

    # Update event
    attendees = changes.attendees.try(&.map { |a| a[:email] }) || existing_attendees
    attendees << cal_id
    attendees.uniq!

    zone = if tz = changes.timezone
             Time::Location.load(tz)
           elsif event_tz = event.start.time_zone
             Time::Location.load(event_tz)
           else
             get_timezone
           end

    event_start = changes.event_start
    event_end = changes.event_end
    event_start = event_start ? event_start : (event.start.date_time || event.start.date).not_nil!.to_unix
    event_end = event_end ? event_end : (event.end.try(&.date_time) || event.end.try(&.date)).not_nil!.to_unix
    all_day = !!event.start.date
    priv = if changes.private == nil
             event.visibility.in?({"private", "confidential"})
           else
             changes.private
           end

    updated_event = calendar.update(
      event.id,
      event_start: Time.unix(event_start).to_local_in(zone),
      event_end: Time.unix(event_end).to_local_in(zone),
      calendar_id: host,
      attendees: attendees,
      all_day: all_day,
      visibility: priv ? Google::Visibility::Private : Google::Visibility::Default,
      location: changes.location || event.location,
      summary: changes.title || event.summary,
      description: changes.body || event.description
    )

    if system
      meta = EventMetadata.find("#{system.id}-#{event.id}") || EventMetadata.new
      meta.system_id = system.id.not_nil!
      meta.event_id = event.id
      meta.event_start = event_start
      meta.event_end = event_end
      meta.resource_calendar = system.email.not_nil!
      meta.host_email = host

      if extension_data = changes.extension_data
        data = meta.extension_data.as_h
        extension_data.as_h.each { |key, value| data[key] = value }
        meta.extension_data = nil
        meta.ext_data = data.to_json
        meta.save!
      end

      # Update PlaceOS with an signal "staff/event/changed"
      spawn do
        sys = system.not_nil!
        placeos_client.root.signal("staff/event/changed", {
          action:    :update,
          system_id: sys.id,
          event_id:  event_id,
          host:      host,
          resource:  sys.email,
        })
      end

      # Grab the list of externals that might be attending
      attending = changes.try &.attendees.try(&.reject { |attendee|
        attendee[:visit_expected].nil?
      })

      if attending
        # Create guests
        attending.each do |attendee|
          email = attendee[:email].strip.downcase
          guest = Guest.find(email) || Guest.new
          guest.email = email
          guest.name ||= attendee[:name]
          guest.save!
        end

        # Create attendees
        attending.each do |attendee|
          email = attendee[:email].strip.downcase
          attend = Attendee.new
          attend.event_id = meta.id.not_nil!
          attend.guest_id = email
          attend.visit_expected = true
          attend.save!
        end
      end

      render json: standard_event(cal_id, system, updated_event, meta)
    else
      render json: standard_event(cal_id, nil, updated_event, nil)
    end
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

      metadata = EventMetadata.find("#{system_id}-#{event_id}")
      render json: standard_event(cal_id, system, event, metadata)
    end

    head :bad_request
  end

  def destroy
    event_id = route_params["id"]
    notify_guests = query_params["notify"]? != "false"
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
      placeos_client = get_placeos_client
      system = placeos_client.systems.fetch(system_id)
      # TODO:: return 404 if system not found
      cal_id = system.email
      head(:not_found) unless cal_id

      EventMetadata.find("#{system_id}-#{event_id}").try &.destroy
      calendar = calendar_for # admin when no user passed
      calendar.delete(event_id, cal_id, notify_option)

      spawn do
        placeos_client.root.signal("staff/event/changed", {
          action:    :cancelled,
          system_id: system.id,
          event_id:  event_id,
          resource:  system.email,
        })
      end

      head :accepted
    end

    head :bad_request
  end

  get("/:id/guests", :guest_list) do
    event_id = route_params["id"]
    render(json: [] of Nil) if query_params["calendar"]?
    system_id = query_params["system_id"]?
    render :bad_request, json: {error: "missing system_id param"} unless system_id

    # Grab meeting metadata if it exists
    metadata = EventMetadata.find("#{system_id}-#{event_id}")
    render(json: [] of Nil) unless metadata

    # Find anyone who is attending
    visitors = metadata.attendees.to_a
    render(json: [] of Nil) if visitors.empty?

    # Grab the guest profiles if they exist
    guests = {} of String => Guest
    Guest.where(:id, :in, visitors.map(&.email)).each { |guest| guests[guest.id.not_nil!] = guest }

    # Merge the visitor data with guest profiles
    visitors = visitors.map { |visitor| attending_guest(visitor, guests[visitor.email]?) }
    render json: visitors
  end

  post("/:id/guests/:guest_id/checkin", :guest_checkin) do
    event_id = route_params["id"]
    guest_email = route_params["guest_id"].downcase
    checkin = (query_params["state"]? || "true") == "true"

    system_id = query_params["system_id"]?
    render :bad_request, json: {error: "missing system_id param"} unless system_id

    metadata_id = "#{system_id}-#{event_id}"

    attendees = Attendee.where(guest_id: guest_email, event_id: metadata_id).limit(1).map { |at| at }
    if attendees.size > 0
      attendee = attendees.first
      attendee.checked_in = checkin
      attendee.save!

      render json: attending_guest(attendee, attendee.guest)
    else
      # possibly this vistor was not expected? We can check if they are in the event
      # TODO::
      head :not_found
    end
  end

  #
  # Event Approval
  #
  post "/:id/approve", :approve do
    update_status("accepted")
  end

  post "/:id/reject", :reject do
    update_status("declined")
  end

  def update_status(status)
    event_id = route_params["id"]
    system_id = query_params["system_id"]

    # Check this system has an associated resource
    system = get_placeos_client.systems.fetch(system_id)
    cal_id = system.email
    head(:not_found) unless cal_id

    # Check the event was in the calendar
    event = get_event(event_id, cal_id)
    head(:not_found) unless event

    # Update the event (user must be a resource approver)
    user_id = user_token.user.email
    calendar = calendar_for(user_id)
    updated_event = calendar.update(
      event_id,
      calendar_id: cal_id,
      attendees: [{
        email:          cal_id,
        responseStatus: status,
      }]
    )

    # Return the full event details
    metadata = EventMetadata.find("#{system.id}-#{event_id}")
    render json: standard_event(cal_id, system, updated_event, metadata)
  end
end
