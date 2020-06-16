require "./attendee"

class Guest < Granite::Base
  connection pg
  table guest

  EMPTY_JSON = JSON.parse("{}")

  def id
    self.email
  end

  def id=(email : String?)
    self.email = email
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
  column searchable : String
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

  has_many :attendees, class_name: Attendee, foreign_key: :guest_id

  def events(future_only = true, limit = 10)
    if future_only
      EventMetadata.all(
        %(WHERE event_end >= ? AND id IN (
          SELECT event_id FROM attendee WHERE guest_id = ?
        ) ORDER BY event_start ASC LIMIT ?), [Time.utc.to_unix, self.id, limit]
      ).map { |e| e }
    else
      EventMetadata.all(
        %(WHERE id IN (
          SELECT event_id FROM attendee WHERE guest_id = ?
        ) ORDER BY event_start ASC LIMIT ?), [self.id, limit]
      ).map { |e| e }
    end
  end

  before_create :downcase_email
  before_save :update_searchable
  before_save :transform_extension_data
  before_destroy :cleanup_attendees

  def attendee_for(event_id : String)
    attend = Attendee.new
    attend.event_id = event_id
    attend.guest = self
    attend.save!
    attend
  end

  def downcase_email
    self.email = self.email.try &.downcase
  end

  def update_searchable
    self.searchable = "#{self.name} #{self.preferred_name} #{organisation} #{id}".downcase
  end

  def cleanup_attendees
    self.attendees.each(&.destroy)
  end

  def transform_extension_data
    if extension_data = @extension_data
      @ext_data = extension_data.to_json
    elsif @ext_data.nil? || @ext_data.try &.empty?
      @ext_data = "{}"
    end
  end

  def attending_today?(timezone)
    now = Time.local(timezone)
    morning = now.at_beginning_of_day.to_unix
    tonight = now.at_end_of_day.to_unix

    Attendee.all(
      %(WHERE guest_id = ? AND event_id IN (
        SELECT id FROM metadata WHERE event_start <= ? AND event_end >= ?
        )
      LIMIT 1
      ), [self.id, tonight, morning]
    ).map { |a| a }.first?
  end
end
