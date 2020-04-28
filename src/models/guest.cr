require "./attendee"

class Guest < Granite::Base
  connection pg
  table guest

  EMPTY_JSON = JSON.parse("{}")

  def id
    self.email
  end

  # A guest can have multiple entries with different emails
  # Profiles are limited to a single email
  column email : String, primary: true, auto: false

  column name : String?
  column preferred_name : String?
  column phone : String?
  column organisation : String?
  column notes : String?
  column photo : String?
  column banned : Bool = false
  column dangerous : Bool = false
  column extension_data : JSON::Any, converter: Granite::Converters::Json(JSON::Any, JSON::Any)

  column searchable : String

  timestamps

  has_many :attendance, class_name: Attendee, foreign_key: "email"
  has_many :events, class_name: EventMetadata, through: :attendance

  before_create :downcase_email
  before_save :update_searchable
  before_destroy :cleanup_attendees

  def downcase_email
    self.email = self.email.try &.downcase
  end

  def update_searchable
    # Limit the chars to 255 characters
    self.searchable = "#{self.name} #{self.preferred_name} #{organisation} #{id}"[0..255].downcase
  end

  def cleanup_attendees
    self.attendance.each { |attend| attend.destroy }
  end
end
