require "uuid"
require "./utilities/*"

abstract class Application < ActionController::Base
  STAFF_DOMAINS = ENV["STAFF_DOMAINS"].split(",").map(&.strip).reject(&.empty?)

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
  rescue_from RethinkORM::Error::DocumentNotFound do |error|
    Log.debug { error.message }
    head :not_found
  end

  # 422 if resource fails validation before mutation
  rescue_from Error::InvalidParams do |error|
    model_errors = error.params.errors.map(&.to_s)
    Log.debug(exception: error) { model_errors }
    render status: :unprocessable_entity, json: model_errors
  end
end
