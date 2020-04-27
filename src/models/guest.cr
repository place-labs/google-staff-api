require "rethinkdb-orm"

class Guest < RethinkORM::Base
  include RethinkORM::Timestamps

  table :guest

  # A guest can have multiple entries with different emails
  # Profiles are limited to a single email
  attribute email : String, mass_assignment: false
  attribute name : String
  attribute preferred_name : String
  attribute phone : String
  attribute organisation : String
  attribute notes : String
  attribute photo : String

  attribute banned : Bool = false
  attribute dangerous : Bool = false

  attribute extension_data : JSON::Any

  validates :name, presence: true
  validates :email, presence: true
  ensure_unique :email

  before_create :generate_id

  def generate_id
    self.id = "guest-#{self.email.downcase}"
  end
end
