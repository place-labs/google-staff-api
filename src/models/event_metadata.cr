require "./attendee"

class EventMetadata < Granite::Base
  connection pg
  table metadata

  # Event details
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
      @ext_data = extension_data.to_json
    elsif @ext_data.nil? || @ext_data.try &.empty?
      @ext_data = "{}"
    end
  end

  def cleanup_attendees
    self.attendees.each(&.destroy)
  end
end
