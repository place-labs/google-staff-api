class Calendars < Application
  base "/api/staff/v1/calendars"

  def index
    render json: get_user_calendars
  end

  get "/availability", :availability do
    candidates = matching_calendar_ids

    # TODO:: perform availability request

    results = candidates.map { |email, system|
      {
        id: email,
        system: system
      }
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
