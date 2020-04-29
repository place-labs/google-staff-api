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

  column searchable : String

  timestamps

  has_many :attendance, class_name: Attendee, foreign_key: "email"
  has_many :events, class_name: EventMetadata, through: :attendance

  before_create :downcase_email
  before_save :update_searchable
  before_save :transform_extension_data
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

  def transform_extension_data
    self.ext_data = extension_data.try(&.to_json) || "{}"
  end
end
