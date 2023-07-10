require "placeos"
require "promise"
require "set"

module Utils::PlaceOSHelpers
  # Base URL of the PlaceOS instance we are interacting with
  PLACE_URI         = App::PLACE_URI
  CALENDAR_WRITABLE = {"writer", "owner"}

  # Get the list of local calendars this user has access to
  def get_user_calendars
    user = user_token.user.email
    primary_found = false
    calendar = calendar_for(user)
    calendars = calendar.calendar_list(Google::Access::Writer).reject { |item| item.deleted }.map do |item|
      primary_found = true if item.id == user
      {
        id:      item.id,
        summary: item.summary,
        primary: !!item.primary,

        # https://developers.google.com/calendar/v3/reference/calendarList#accessRole
        # https://docs.microsoft.com/en-us/graph/api/user-list-calendars?view=graph-rest-1.0&tabs=http#response-1
        can_edit: item.access_role.in?(CALENDAR_WRITABLE),
        hidden:   item.hidden,
      }
    end
    if !primary_found
      calendars << {
        id:       user,
        summary:  user_token.user.name,
        primary:  true,
        can_edit: true,
        hidden:   false,
      }
    end
    calendars
  end

  @client : PlaceOS::Client? = nil

  def get_placeos_client : PlaceOS::Client
    @client ||= if key = request.headers["X-API-Key"]?
      PlaceOS::Client.new(
        PLACE_URI,
        host_header: request.headers["Host"]?,
        insecure: true,
        x_api_key: key
      )
    else
      PlaceOS::Client.new(
        PLACE_URI,
        token: OAuth2::AccessToken::Bearer.new(acquire_token.not_nil!, nil),
        host_header: request.headers["Host"]?,
        insecure: true
      )
    end
  end

  class CalendarSelection < Params
    attribute calendars : String?
    attribute zone_ids : String?
    attribute system_ids : String?
    attribute features : String?
    attribute capacity : Int32?
    attribute bookable : Bool?
  end

  def matching_calendar_ids
    args = CalendarSelection.new(params)
    # Create a map of calendar ids to systems
    system_calendars = {} of String => PlaceOS::Client::API::Models::System?

    # only obtain events for calendars the user has access to
    calendars = Set.new((args.calendars || "").split(',').map(&.strip.downcase).reject(&.empty?))
    if calendars.size > 0
      (calendars & Set.new(get_user_calendars.map { |cal| cal[:id] })).each do |calendar|
        system_calendars[calendar] = nil
      end
    end

    # Check if we want to grab systems from zones
    zones = (args.zone_ids || "").split(',').map(&.strip).reject(&.empty?).uniq
    if zones.size > 0
      client = get_placeos_client.systems

      # perform requests in parallel (map-reduce)
      Promise.all(zones.map { |zone_id|
        Promise.defer {
          client.search(
            limit: 10_000,
            zone_id: zone_id,
            features: args.features,
            capacity: args.capacity,
            bookable: args.bookable
          )
        }.catch { |error|
          Log.warn { "error fetching zone id #{zone_id}: #{error.message || ""}" }
          error
        }
      }).get.each do |results|
        results.each do |system|
          calendar = system.email
          next unless calendar
          next if calendar.empty?
          system_calendars[calendar] = system
        end
      end
    end

    # Check if we want to grab individual systems
    system_ids = (args.system_ids || "").split(',').map(&.strip).reject(&.empty?).uniq
    if system_ids.size > 0
      client = get_placeos_client.systems

      # perform requests in parallel (map-reduce)
      Promise.all(system_ids.map { |system_id|
        Promise.defer { client.fetch(system_id) }.catch { |error|
          Log.warn { "error fetching system id #{system_id}: #{error.message || ""}" }
          error
        }
      }).get.each do |system|
        calendar = system.email
        next unless calendar
        next if calendar.empty?
        system_calendars[calendar] = system
      end
    end

    system_calendars
  end

  enum Access
    None
    Manage
    Admin
  end

  class PermissionsMeta
    include JSON::Serializable

    getter deny : Array(String)?
    getter manage : Array(String)?
    getter admin : Array(String)?

    # Returns {permission_found, access_level}
    def has_access?(groups : Array(String)) : Tuple(Bool, Access)
      case
      when (none = deny) && !(none & groups).empty?
        {false, Access::None}
      when (can_manage = manage) && !(can_manage & groups).empty?
        {true, Access::Manage}
      when (can_admin = admin) && !(can_admin & groups).empty?
        {true, Access::Admin}
      else
        {false, Access::None}
      end
    end
  end

  # https://docs.google.com/document/d/1OaZljpjLVueFitmFWx8xy8BT8rA2lITyPsIvSYyNNW8/edit#
  # See the section on user-permissions
  def check_access(groups : Array(String), check : Array(String))
    Log.info { "checking groups #{groups} have access in #{check}" }
    client = get_placeos_client.metadata
    access = Access::None
    check.each do |area_id|
      Log.info { " --> checking permissions in #{area_id}" }
      if metadata = client.fetch(area_id, "permissions")["permissions"]?.try(&.details)
        continue, access = PermissionsMeta.from_json(metadata.to_json).has_access?(groups)
        Log.info { " --! found permissions: #{metadata} - continue: #{continue}, access: #{access}" }
        break unless continue
      end
    end
    Log.info { " <-- final permission: #{access}" }
    access
  end
end
