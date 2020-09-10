class Guests < Application
  base "/api/staff/v1/guests"

  before_action :find_guest, only: [:show, :update, :update_alt, :destroy, :meetings]
  getter guest : Guest { find_guest }

  # Skip scope check for relevant routes
  skip_action :check_jwt_scope, only: [:show, :update]

  def index
    query = (query_params["q"]? || "").gsub(/[^\w\s]/, "").strip.downcase
    starting = query_params["period_start"]?
    if starting
      period_start = Time.unix(starting.to_i64)
      period_end = Time.unix(query_params["period_end"].to_i64)

      # We want a subset of the calendars
      calendars = matching_calendar_ids
      render(json: [] of Nil) if calendars.empty?

      user = user_token.user.email
      calendar = calendar_for(user)

      # Grab events in batches
      requests = [] of HTTP::Request
      mappings = calendars.map { |calendar_id, system|
        request = calendar.events_request(
          calendar_id,
          period_start,
          period_end,
          showDeleted: false
        )
        requests << request
        {request, calendar_id, system}
      }
      responses = calendar.batch(requests)

      # Process the response (map requests back to responses)
      errors = 0
      results = [] of Tuple(String, PlaceOS::Client::API::Models::System?, Google::Calendar::Event)
      mappings.each do |(request, calendar_id, system)|
        begin
          results.concat calendar.events(responses[request]).items.map { |event| {calendar_id, system, event} }
        rescue error
          Log.warn(exception: error) { "error fetching events for #{calendar_id}" }
        end
      end
      response.headers["X-Calendar-Errors"] = errors.to_s if errors > 0

      # Grab any existing eventmeta data
      metadata_ids = Set(String).new
      metadata_recurring_ids = Set(String).new
      meeting_lookup = {} of String => Tuple(PlaceOS::Client::API::Models::System, Google::Calendar::Event)
      results.each { |(calendar_id, system, event)|
        if system
          metadata_id = "#{system.id}-#{event.id}"
          metadata_ids << metadata_id
          meeting_lookup[metadata_id] = {system, event}
          if event.recurring_event_id
            metadata_id = "#{system.id}-#{event.recurring_event_id}"
            metadata_ids << metadata_id
            metadata_recurring_ids << metadata_id
            meeting_lookup[metadata_id] = {system, event}
          end
        end
      }

      # Don't perform the query if there are no calendar entries
      render(json: [] of Nil) if metadata_ids.empty?

      # Return the guests visiting today
      attendees = {} of String => Attendee
      attended_metadata_ids = Set(String).new
      Attendee.where(:event_id, :in, metadata_ids.to_a).each do |attend|
        attend.checked_in = false if attend.event_id.in?(metadata_recurring_ids)
        attendees[attend.guest_id] = attend
        attended_metadata_ids << attend.event_id
      end

      render(json: [] of Nil) if attendees.empty?

      # Grab as much information about the guests as possible
      guests = {} of String => Guest
      Guest.where(:email, :in, attendees.keys).each { |guest| guests[guest.email.not_nil!] = guest }

      render json: attendees.map { |email, visitor|
        # Prevent a database lookup
        include_meeting = nil
        if meet = meeting_lookup[visitor.event_id]?
          system, event = meet
          include_meeting = {
            id:          event.id,
            status:      event.status,
            title:       event.summary,
            host:        event.organizer.try &.email,
            creator:     event.creator.try &.email,
            private:     event.visibility.in?({"private", "confidential"}),
            event_start: event.start.time.to_unix,
            event_end:   event.end.try { |time| (time.date_time || time.date).try &.to_unix },
            timezone:    event.start.time_zone,
            all_day:     !!event.start.date,
            system:      system,
          }
        end
        attending_guest(visitor, guests[email]?, meeting_details: include_meeting)
      }
    elsif query.empty?
      # Return the first 1500 guests
      render json: Guest.order(:name).limit(1500).map { |g| attending_guest(nil, g) }
    else
      # Return guests based on the filter query
      query = "%#{query}%"
      render json: Guest.all("WHERE searchable LIKE ? LIMIT 1500", [query]).map { |g| attending_guest(nil, g) }
    end
  end

  def show
    if user_token.scope.includes?("guest")
      head :forbidden unless guest.id == user_token.sub
    end

    # find out if they are attending today
    attendee = guest.attending_today?(get_timezone)
    render json: attending_guest(attendee, guest)
  end

  def update
    if user_token.scope.includes?("guest")
      head :forbidden unless guest.id == user_token.sub
    end

    changes = Guest.from_json(request.body.as(IO))
    {% for key in [:name, :preferred_name, :phone, :organisation, :notes, :photo, :banned, :dangerous] %}
      begin
        guest.{{key.id}} = changes.{{key.id}}
      rescue NilAssertionError
      end
    {% end %}

    # merge changes into extension data
    data = guest.extension_data
    changes.extension_data.each { |key, value| data[key] = value }
    guest.extension_data = nil
    guest.ext_data = data.to_json

    if guest.save
      attendee = guest.attending_today?(get_timezone)
      render json: attending_guest(attendee, guest), status: HTTP::Status::OK
    else
      render json: guest.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  put "/:id", :update_alt { update }

  def create
    guest = Guest.from_json(request.body.as(IO))
    if guest.save
      attendee = guest.attending_today?(get_timezone)
      render json: attending_guest(attendee, guest), status: HTTP::Status::CREATED
    else
      render json: guest.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  def destroy
    guest.destroy
    head :accepted
  end

  get("/:id/meetings", :meetings) do
    future_only = query_params["include_past"]? != "true"
    limit = (query_params["limit"]? || "10").to_i

    placeos_client = get_placeos_client.systems
    calendar = calendar_for(user_token.user.email)

    events = Promise.all(guest.events(future_only, limit).map { |metadata|
      Promise.defer {
        cal_id = metadata.resource_calendar.not_nil!
        system = placeos_client.fetch(metadata.system_id.not_nil!)
        event = calendar.event(metadata.event_id.not_nil!, cal_id)
        if event
          standard_event(cal_id, system, event, metadata)
        else
          nil
        end
      }
    }).get.compact
    render json: events
  end

  # ============================================
  #              Helper Methods
  # ============================================

  def find_guest
    # Find will raise a 404 (not found) if there is an error
    Guest.find!(route_params["id"])
  end
end
