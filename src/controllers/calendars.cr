class Calendars < Application
  base "/api/staff/v1/calendars"

  def index
    render json: get_user_calendars
  end

  get "/availability", :availability do
    # Grab the system emails
    candidates = matching_calendar_ids
    calendars = candidates.keys

    # Append calendars you might not have direct access too
    # As typically a staff member can see anothers availability
    all_calendars = Set.new((params["calendars"]? || "").split(',').map(&.strip.downcase).reject(&.empty?))
    all_calendars.concat(calendars)
    calendars = all_calendars.to_a
    render(json: [] of String) if calendars.empty?

    # Grab the user
    user = user_token.user.email
    calendar = calendar_for(user)

    # perform availability request
    period_start = Time.unix(query_params["period_start"].to_i64)
    period_end = Time.unix(query_params["period_end"].to_i64)

    requests = [] of HTTP::Request
    calendars.in_groups_of(50) do |cals|
      # in_groups_of appends nil values when less than the group size
      requests << calendar.availability_request(cals.compact, period_start, period_end)
    end

    busy = [] of Google::Calendar::CalendarAvailability
    calendar.batch(requests).values.each do |response|
      busy.concat calendar.availability(response)
    end

    # Remove any rooms that have overlapping bookings
    calendar_errors = 0
    busy.each do |status|
      if status.error || status.availability.size > 0
        if err = status.error
          Log.info { "error requesting availability for #{status.calendar}: #{err}" }
          calendar_errors += 1
        end
        calendars.delete(status.calendar.downcase)
      end
    end
    response.headers["X-Calendar-Errors"] = calendar_errors.to_s if calendar_errors > 0

    # Return the results
    results = calendars.map { |email|
      if system = candidates[email]?
        {
          id:     email,
          system: system,
        }
      else
        {
          id: email,
        }
      end
    }

    render json: results
  end

  get "/free_busy", :free_busy do
    # Grab the system emails
    candidates = matching_calendar_ids
    calendars = candidates.keys

    # Append calendars you might not have direct access too
    # As typically a staff member can see anothers availability
    all_calendars = Set.new((params["calendars"]? || "").split(',').map(&.strip.downcase).reject(&.empty?))
    all_calendars.concat(calendars)
    calendars = all_calendars.to_a
    render(json: [] of String) if calendars.empty?

    # Grab the user
    user = user_token.user.email
    calendar = calendar_for(user)

    # perform availability request
    period_start = Time.unix(query_params["period_start"].to_i64)
    period_end = Time.unix(query_params["period_end"].to_i64)

    requests = [] of HTTP::Request
    calendars.in_groups_of(50) do |cals|
      # in_groups_of appends nil values when less than the group size
      requests << calendar.availability_request(cals.compact, period_start, period_end)
    end

    busy = [] of Google::Calendar::CalendarAvailability
    calendar.batch(requests).values.each do |response|
      busy.concat calendar.availability(response)
    end

    # Return the results
    calendar_errors = 0
    results = busy.compact_map { |details|
      if err = details.error
        Log.info { "error requesting availability for #{details.calendar}: #{err}" }
        calendar_errors += 1
        next
      end

      if system = candidates[details.calendar]?
        {
          id:           details.calendar,
          system:       system,
          availability: details.availability,
        }
      else
        {
          id:           details.calendar,
          availability: details.availability,
        }
      end
    }
    response.headers["X-Calendar-Errors"] = calendar_errors.to_s if calendar_errors > 0
    render json: results
  end

  # configure the database
  def create
    head(:forbidden) unless is_admin?
    EventMetadata.migrator.drop_and_create
    Attendee.migrator.drop_and_create
    Booking.migrator.drop_and_create
    Guest.migrator.drop_and_create
    head :ok
  end
end
