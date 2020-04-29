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
  column event_start : Time
  column event_end : Time

  column ext_data : String?, converter: Granite::Converters::Json(String, Bytes)

  property extension_data : JSON::Any?

  def extension_data : JSON::Any?
    if @extension_data
      @extension_data
    else
      data = self.ext_data
      @extension_data = JSON.parse(data) if data
    end
  end

  timestamps

  has_many :attendees, class_name: Attendee, foreign_key: "event_id"

  before_create :generate_id
  before_save :transform_extension_data

  def generate_id
    self.id = "#{self.system_id}-#{self.event_id}"
  end

  def transform_extension_data
    self.ext_data = extension_data.try(&.to_json) || "{}"
  end
end
