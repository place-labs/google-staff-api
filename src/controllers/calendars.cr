class Calendars < Application
  base "/api/staff/v1/calendars"

  def index
    render json: get_user_calendars
  end

  get "/availability", :availability do
    candidates = matching_calendar_ids

    # TODO:: perform availability request

    render json: candidates
  end

  # configure the database
  def destroy
    # TODO:: add some basic auth here
    EventMetadata.migrator.drop_and_create
    Attendee.migrator.drop_and_create
    Guest.migrator.drop_and_create
    head :ok
  end
end
