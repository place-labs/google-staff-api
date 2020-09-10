require "./attendee"

class EventMetadata < Granite::Base
  connection pg
  table metadata

  # Event details
  # NOTE:: Using this as the ID is a bad idea
  # should have a seperate indexed column for lookup so it's simple to migrate guests
  # if a meeting is moved to a new room
  column id : String, primary: true, auto: false

  column system_id : String
  column event_id : String

  column host_email : String
  column resource_calendar : String
  column event_start : Int64
  column event_end : Int64

  column ext_data : String?

  property extension_data : JSON::Any?

  def extension_data : JSON::Any
    if json_data = @extension_data
      json_data
    else
      data = self.ext_data
      @extension_data = data ? JSON.parse(data) : JSON.parse("{}")
    end
  end

  timestamps

  has_many :attendees, class_name: Attendee, foreign_key: :event_id

  before_create :generate_id
  before_save :transform_extension_data
  before_destroy :cleanup_attendees

  def generate_id
    self.id = "#{self.system_id}-#{self.event_id}"
  end

  def transform_extension_data
    if extension_data = @extension_data
      self.ext_data = extension_data.to_json
    elsif self.ext_data.presence.nil?
      self.ext_data = "{}"
    end
  end

  def cleanup_attendees
    self.attendees.each(&.destroy)
  end

  def self.migrate_recurring_metadata(system_id : String, recurrance : Google::Calendar::Event, parent_metadata : EventMetadata)
    begin
      metadata = EventMetadata.new
      metadata.extension_data = parent_metadata.extension_data
      metadata.system_id = system_id
      metadata.event_id = recurrance.id
      metadata.event_start = recurrance.start.not_nil!.time.to_unix
      metadata.event_end = recurrance.end.not_nil!.time.to_unix
      metadata.resource_calendar = parent_metadata.resource_calendar
      metadata.host_email = parent_metadata.host_email
      metadata.save!
    rescue ::Granite::RecordNotSaved
      # if two requests requests trigger a migrate simultaneously then one will lose
      # super hacky but should do the trick to prevent client side errors
      sleep 1
      return
    end

    parent_metadata.attendees.each do |attendee|
      if attendee.visit_expected
        attend = Attendee.new
        attend.event_id = metadata.id.not_nil!
        attend.guest_id = attendee.guest_id
        attend.visit_expected = true
        attend.save!
      end
    end

    nil
  end
end
