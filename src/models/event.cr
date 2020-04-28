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

    property range_start : Int64
    property range_end : Int64

    # Bit mask
    property days_of_week : DaysOfWeek?
    # defaults to 1
    property interval : Int32?
    property pattern : Pattern
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
