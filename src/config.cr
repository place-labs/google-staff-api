# Application dependencies
require "action-controller"
require "active-model"
require "./constants"

# Application code
require "granite/adapter/pg"
Granite::Connections << Granite::Adapter::Pg.new(name: "pg", url: App::PG_DATABASE_URL)

require "./error"
require "./controllers/application"
require "./controllers/*"
require "./models/*"

# Server required after application controllers
require "action-controller/server"

# Configure logging
Log.builder.bind "*", :warning, App::LOG_BACKEND
Log.builder.bind "action-controller.*", :info, App::LOG_BACKEND
Log.builder.bind "#{App::NAME}.*", :info, App::LOG_BACKEND

# Filter out sensitive params that shouldn't be logged
filter_params = ["password", "bearer_token"]
keeps_headers = ["X-Request-ID"]

# Add handlers that should run before your application
ActionController::Server.before(
  ActionController::ErrorHandler.new(App.running_in_production?, keeps_headers),
  ActionController::LogHandler.new(filter_params)
)

# Configure session cookies
# NOTE:: Change these from defaults
ActionController::Session.configure do |settings|
  settings.key = App::COOKIE_SESSION_KEY
  settings.secret = App::COOKIE_SESSION_SECRET
  # HTTPS only:
  settings.secure = App.running_in_production?
end
