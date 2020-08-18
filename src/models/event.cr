class CalendarEvent
  include JSON::Serializable

  class Attendee
    include JSON::Serializable

    property name : String?
    property email : String
  end

  class Attachment
    include JSON::Serializable

    property name : String
    property blob : Bytes
  end

  # Google has a free-form text field for this
  # Office365 has a more complicated JSON format
  class Location
    include JSON::Serializable

    # Room name etc
    property text : String?
    # Actual street address
    property address : String?
    # Geolocation
    property coordinates : NamedTuple(lat: String, long: String)?
  end

  class Recurrence
    include JSON::Serializable

    @[Flags]
    enum DaysOfWeek
      Sunday  # 1
      Monday  # 2
      Tuesday # 4
      Wednesday
      Thursday
      Friday
      Saturday
    end

    enum Pattern
      Day
      Week
      Month
      MonthRelative
      Year
    end

    @[JSON::Field(converter: Time::EpochConverter)]
    property range_start : Time

    @[JSON::Field(converter: Time::EpochConverter)]
    property range_end : Time

    # "SU" / "MO" / "TU" / "WE" / "TH" / "FR" / "SA" https://tools.ietf.org/html/rfc5545
    property days_of_week : String?
    # defaults to 1
    property interval : Int32?
    property pattern : String

    def self.recurrence_to_google(recurrence)
      interval = recurrence.interval || 1
      pattern = recurrence.pattern
      days_of_week = recurrence.days_of_week

      formatted_until_date = recurrence.range_end.to_rfc3339.gsub("-", "").gsub(":", "").split(".").first
      until_date = "#{formatted_until_date}"
      case pattern
      when "daily"
        ["RRULE:FREQ=#{pattern.upcase};INTERVAL=#{interval};UNTIL=#{until_date}"]
      when "weekly"
        ["RRULE:FREQ=#{pattern.upcase};INTERVAL=#{interval};BYDAY=#{days_of_week.not_nil!.upcase[0..1]};UNTIL=#{until_date}"]
      when "monthly"
        ["RRULE:FREQ=#{pattern.upcase};INTERVAL=#{interval};BYDAY=1#{days_of_week.not_nil!.upcase[0..1]};UNTIL=#{until_date}"]
      end
    end

    def self.recurrence_from_google(recurrence_rule, event)
      rule_parts = recurrence_rule.not_nil!.first.split(";")
      location = event.start.time_zone ? Time::Location.load(event.start.time_zone.not_nil!) : Time::Location.load("UTC")
      PlaceCalendar::Recurrence.new(range_start: event.start.time.at_beginning_of_day.in(location),
        range_end: google_range_end(rule_parts, event),
        interval: google_interval(rule_parts),
        pattern: google_pattern(rule_parts),
        days_of_week: google_days_of_week(rule_parts),
      )
    end

    private def self.google_pattern(rule_parts)
      pattern_part = rule_parts.find do |parts|
        parts.includes?("RRULE:FREQ")
      end.not_nil!

      pattern_part.split("=").last.downcase
    end

    private def self.google_interval(rule_parts)
      interval_part = rule_parts.find do |parts|
        parts.includes?("INTERVAL")
      end.not_nil!

      interval_part.split("=").last.to_i
    end

    private def self.google_range_end(rule_parts, event)
      range_end_part = rule_parts.find do |parts|
        parts.includes?("UNTIL")
      end.not_nil!
      until_date = range_end_part.gsub("Z", "").split("=").last
      location = event.start.time_zone ? Time::Location.load(event.start.time_zone.not_nil!) : Time::Location.load("UTC")

      Time.parse(until_date, "%Y%m%dT%H%M%S", location)
    end

    private def self.google_days_of_week(rule_parts)
      byday_part = rule_parts.find do |parts|
        parts.includes?("BYDAY")
      end

      if byday_part
        byday = byday_part.not_nil!.split("=").last

        case byday
        when "SU", "1SU"
          "sunday"
        when "MO", "1MO"
          "monday"
        when "TU", "1TU"
          "tuesday"
        when "WE", "1WE"
          "wednesday"
        when "TH", "1TH"
          "thursday"
        when "FR", "1FR"
          "friday"
        when "SA", "1SA"
          "saturday"
        end
      end
    end
  end

  # Host is the email of the person who will be attending the meeting
  # The optional calendar field is for Office365 where a host may have multiple
  # calendars and this event is to target something other than the default
  property host : String
  property calendar : String?

  # This field should be set if the person who created this meeting is not the host
  # i.e. created by a secretary or a concierge
  property creator : String?

  # Who is attending the meeting (including resources like meeting rooms)
  property attendees : Array(Attendee)

  property title : String
  property body : String?
  property attachments : Array(Attachment)?
  property private : Bool?

  # start and end times of a meeting as a UNIX epoch
  property event_start : Int64
  property event_end : Int64
  # timezone as IANA timezone
  property timezone : String
  property all_day : Bool?

  property location : Array(Location)?

  property recurring : Bool?
  # This really only needs to be set for event creation
  # No need to send this data when viewing events
  property recurrence : Recurrence?
  property recurrence_master_id : String?

  # Optional extension data that by default won't come down when viewing events
  property extension_data : Hash(String, JSON::Any)?
end
