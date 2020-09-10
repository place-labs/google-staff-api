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

      calendar = calendar_for
      responses = Promise.all(calendars.map { |calendar_id, system|
        Promise.defer {
          events = calendar.events(
            calendar_id,
            period_start,
            period_end,
            showDeleted: false
          ).items.map { |event| {calendar_id, system, event} }

          # no error, the cal id and the list of the events
          {"", calendar_id, events}
        }.catch { |error|
          sys_name = system.try(&.name)
          calendar_id = sys_name ? "#{sys_name} (#{calendar_id})" : calendar_id
          {error.message || "", calendar_id, [] of Tuple(String, PlaceOS::Client::API::Models::System?, Google::Calendar::Event)}
        }
      }).get

      # if there are any errors let's log them and expose them via the API
      # done outside the promise so we have all the tagging associated with this fiber
      calendar_errors = [] of String
      responses.select { |result| result[0].presence }.each do |error|
        calendar_id = error[1]
        calendar_errors << calendar_id
        Log.warn { "error fetching events for #{calendar_id}: #{error[0]}" }
      end
      response.headers["X-Calendar-Errors"] = calendar_errors unless calendar_errors.empty?

      # return the valid results
      results = responses.map { |result| result[2] }.flatten

      # Grab any existing eventmeta data
      metadata_ids = Set(String).new
      metadata_recurring_ids = Set(String).new
      results.each { |(calendar_id, system, event)|
        if system
          metadata_ids << "#{system.id}-#{event.id}"
          if event.recurring_event_id
            metadata_id = "#{system.id}-#{event.recurring_event_id}"
            metadata_ids << metadata_id
            metadata_recurring_ids << metadata_id
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

      # Obtain the meeting data for each guest
      metadata_lookup = {} of String => EventMetadata
      EventMetadata.where(:id, :in, attended_metadata_ids.to_a).each { |evt| metadata_lookup[evt.id.not_nil!] = evt }

      render json: attendees.map { |email, visitor|
        # Prevent a database lookup
        include_meeting = false
        if meeting = metadata_lookup[visitor.event_id]?
          visitor.event = meeting
          include_meeting = true
        end
        attending_guest(visitor, guests[email]?, include_meeting_details: include_meeting)
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
