require "uuid"
require "./utilities/*"

abstract class Application < ActionController::Base
  STAFF_DOMAINS = ENV["STAFF_DOMAINS"].split(",").map(&.strip).reject(&.empty?)
  # TODO:: Move this to user model
  DEFAULT_TIME_ZONE = Time::Location.load(ENV["STAFF_TIME_ZONE"]? || "Australia/Sydney")

  # Helpers for determing picking off user from JWT, authorization
  include Utils::PlaceOSHelpers
  include Utils::GoogleHelpers
  include Utils::CurrentUser
  include Utils::Responders

  # ============================
  # LOGGING
  # ============================
  Log = ::App::Log.for("controller")
  before_action :configure_request_logging
  @request_id : String? = nil

  # This makes it simple to match client requests with server side logs.
  # When building microservices this ID should be propagated to upstream services.
  def configure_request_logging
    @request_id = request_id = UUID.random.to_s
    Log.context.set(
      client_ip: client_ip,
      request_id: request_id,
      user_id: user_token.id
    )
    response.headers["X-Request-ID"] = request_id
  end

  # ============================
  # JWT Scope Check
  # ============================
  before_action :check_jwt_scope

  def check_jwt_scope
    unless user_token.scope.includes?("public")
      Log.warn { {message: "unknown scope #{user_token.scope}", action: "authorize!", host: request.hostname, sub: user_token.id} }
      raise Error::Unauthorized.new "valid scope required for access"
    end
  end

  # ============================================
  #              Helper Methods
  # ============================================

  def get_event(event_id, cal_id)
    calendar = calendar_for(user_token.user.email)
    calendar.event(event_id, cal_id)
  end

  # Grab the users timezone
  def get_timezone
    tz = query_params["timezone"]?
    if tz && !tz.empty?
      Time::Location.load(URI.decode(tz))
    else
      DEFAULT_TIME_ZONE
    end
  end

  def attending_guest(visitor : Attendee?, guest : Guest?, parent_meta = false, meeting_details = nil)
    result = if guest
               {% begin %}
                {
                  {% for key in [:email, :name, :preferred_name, :phone, :organisation, :notes, :photo, :banned, :dangerous, :extension_data] %}
                    {{key.id}}: guest.{{key.id}},
                  {% end %}
                  checked_in:     parent_meta ? false : visitor.try(&.checked_in) || false,
                  visit_expected: visitor.try(&.visit_expected) || false,
                }
               {% end %}
             elsif visitor
               {
                 email:          visitor.email,
                 checked_in:     parent_meta ? false : visitor.checked_in,
                 visit_expected: visitor.visit_expected,
               }
             else
               raise "requires either an attendee or a guest"
             end

    result = result.merge({event: meeting_details}) if meeting_details
    result
  end

  # So we don't have to allocate array objects
  NOP_ATTEND   = [] of Attendee
  NOP_G_ATTEND = [] of ::Google::Calendar::Attendee

  def standard_event(calendar_id, system, event, metadata, is_parent_metadata = false)
    visitors = {} of String => Attendee
    (metadata.try(&.attendees) || NOP_ATTEND).each { |vis| visitors[vis.email] = vis }

    # Grab the list of external visitors
    attendees = (event.attendees || NOP_G_ATTEND).map do |attendee|
      email = attendee.email.downcase
      if visitor = visitors[email]?
        {
          name:            attendee.display_name || email,
          email:           email,
          response_status: attendee.response_status,
          checked_in:      is_parent_metadata ? false : visitor.checked_in,
          visit_expected:  visitor.visit_expected,
          resource:        attendee.resource,
        }
      else
        {
          name:            attendee.display_name || email,
          email:           email,
          response_status: attendee.response_status,
          organizer:       attendee.organizer,
          resource:        attendee.resource,
        }
      end
    end

    event_start = (event.start.date_time || event.start.date).not_nil!.to_unix
    event_end = event.end.try { |time| (time.date_time || time.date).try &.to_unix }

    # Ensure metadata is in sync
    if metadata && (event_start != metadata.event_start || (event_end && event_end != metadata.event_end))
      metadata.event_start = start_time = event_start
      metadata.event_end = event_end ? event_end : (start_time + 24.hours.to_i)
      metadata.save
    end

    # recurring events
    recurring = false
    recurrence = if recur = event.recurrence
                   recurring = true
                   CalendarEvent::Recurrence.recurrence_from_google(recur, event)
                 end

    # TODO:: location

    {
      id:             event.id,
      status:         event.status,
      calendar:       calendar_id,
      title:          event.summary,
      body:           event.description,
      location:       event.location,
      host:           event.organizer.try &.email,
      creator:        event.creator.try &.email,
      private:        event.visibility.in?({"private", "confidential"}),
      event_start:    event_start,
      event_end:      event_end,
      timezone:       event.start.time_zone,
      all_day:        !!event.start.date,
      attendees:      attendees,
      system:         system,
      extension_data: metadata.try(&.extension_data) || {} of Nil => Nil,
      recurring:      recurring,
      recurrence:     recurrence,
      # MS version of this https://docs.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0#properties
      # seriesMasterId
      recurring_master_id: event.recurring_event_id,
    }
  end

  # Error Handlers
  ###########################################################################

  # 400 if unable to parse some JSON passed by a client
  rescue_from JSON::MappingError do |error|
    Log.debug { error.inspect_with_backtrace }

    if App.running_in_production?
      respond_with(:bad_request) do
        text error.message
        json({error: error.message})
      end
    else
      respond_with(:bad_request) do
        text error.inspect_with_backtrace
        json({
          error:     error.message,
          backtrace: error.backtrace?,
        })
      end
    end
  end

  rescue_from JSON::ParseException do |error|
    Log.debug { error.inspect_with_backtrace }

    if App.running_in_production?
      respond_with(:bad_request) do
        text error.message
        json({error: error.message})
      end
    else
      respond_with(:bad_request) do
        text error.inspect_with_backtrace
        json({
          error:     error.message,
          backtrace: error.backtrace?,
        })
      end
    end
  end

  # 401 if no bearer token
  rescue_from Error::Unauthorized do |error|
    Log.debug { error.message }
    head :unauthorized
  end

  # 403 if user role invalid for a route
  rescue_from Error::Forbidden do |error|
    Log.debug { error.inspect_with_backtrace }
    head :forbidden
  end

  # 404 if resource not present
  rescue_from Granite::Querying::NotFound do |error|
    Log.debug { error.message }
    head :not_found
  end

  # 422 if resource fails validation before mutation
  rescue_from Error::InvalidParams do |error|
    model_errors = error.params.errors.map(&.to_s)
    Log.debug(exception: error) { model_errors }
    render status: :unprocessable_entity, json: model_errors
  end

  # 404 if resource not present
  rescue_from PQ::PQError do |error|
    Log.debug { error.inspect_with_backtrace }
    respond_with(:internal_server_error) do
      text error.inspect_with_backtrace
      json({
        error:     error.message,
        backtrace: error.backtrace?,
        fields:    error.fields.map(&.inspect),
      })
    end
  end
end
