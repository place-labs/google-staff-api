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

  column extension_data : JSON::Any, converter: Granite::Converters::Json(JSON::Any, JSON::Any)
  timestamps

  has_many :attendees, class_name: Attendee, foreign_key: "event_id"

  before_create :generate_id

  def generate_id
    self.id = "#{self.system_id}-#{self.event_id}"
  end
end
