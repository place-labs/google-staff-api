require "rethinkdb-orm"

class Attendee < RethinkORM::Base
  include RethinkORM::Timestamps

  table :attendee

  attribute email : String
  attribute event_id : String
  attribute checked_in : Bool = false
  attribute visit_expected : Bool = true

  belongs_to EventMetadata, foreign_key: "metadata_id"
  validates :metadata_id, presence: true

  ensure_unique :email, scope: [:metadata_id, :email] do |system_id, event_id|
    {metadata_id, email}
  end

  def guest_details
    Guest.find("guest-#{self.email}")
  end
end
