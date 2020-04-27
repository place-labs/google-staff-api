require "rethinkdb-orm"
require "time"
require "./attendee"

class EventMetadata < RethinkORM::Base
  include RethinkORM::Timestamps

  table :event_metadata

  # Event details
  attribute system_id : String
  attribute event_id : String

  attribute host_email : String
  attribute resource_calendar : String
  attribute event_start : Time, converter: Time::EpochConverter
  attribute event_end : Time, converter: Time::EpochConverter

  has_many(
    child_class: Attendee,
    dependent: :destroy,
    foreign_key: "metadata_id",
    collection_name: :attendees
  )

  attribute extension_data : JSON::Any

  validates :system_id, presence: true
  validates :event_id, presence: true
  validates :host_email, presence: true
  validates :resource_calendar, presence: true
  validates :event_start, presence: true
  validates :event_end, presence: true

  ensure_unique :event_id, scope: [:system_id, :event_id] do |system_id, event_id|
    {system_id, event_id}
  end

  before_create :generate_id

  def generate_id
    self.id = "meta-#{self.system_id}-#{self.event_id}"
  end
end
