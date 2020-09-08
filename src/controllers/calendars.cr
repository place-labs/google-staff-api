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
    busy = calendar.availability(calendars, period_start, period_end)

    # Remove any rooms that have overlapping bookings
    busy.each { |status| calendars.delete(status.calendar.downcase) unless status.availability.empty? }

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
    busy = calendar.availability(calendars, period_start, period_end)

    # Return the results
    results = busy.map { |details|
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
