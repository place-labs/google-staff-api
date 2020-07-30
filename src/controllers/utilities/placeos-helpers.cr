require "placeos"
require "promise"
require "set"

module Utils::PlaceOSHelpers
  # Base URL of the PlaceOS instance we are interacting with
  PLACE_URI = App::PLACE_URI

  # Get the list of local calendars this user has access to
  def get_user_calendars
    user = user_token.user.email
    calendar = calendar_for(user)
    calendar.calendar_list.reject { |item|
      item.hidden || item.deleted
    }.map do |item|
      {
        id:      item.id,
        summary: item.summary,
        primary: !!item.primary,
      }
    end
  end

  @client : PlaceOS::Client? = nil

  def get_placeos_client : PlaceOS::Client
    @client ||= PlaceOS::Client.new(
      PLACE_URI,
      token: OAuth2::AccessToken::Bearer.new(acquire_token.not_nil!, nil)
    )
  end

  class CalendarSelection < Params
    attribute calendars : String
    attribute zone_ids : String
    attribute system_ids : String
    attribute features : String
    attribute capacity : Int32
    attribute bookable : Bool
  end

  def matching_calendar_ids
    args = CalendarSelection.new(params)
    # Create a map of calendar ids to systems
    system_calendars = {} of String => PlaceOS::Client::API::Models::System?

    # only obtain events for calendars the user has access to
    calendars = Set.new((args.calendars || "").split(',').map(&.strip).reject(&.empty?))
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
end
