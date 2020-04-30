require "./event_metadata"
require "./guest"

class Attendee < Granite::Base
  connection pg
  table attendee

  column id : Int64, primary: true

  belongs_to event : EventMetadata, primary_key: "id", foreign_key: event_id : String
  belongs_to guest : Guest, primary_key: "id", foreign_key: guest_id : String

  column checked_in : Bool = false
  column visit_expected : Bool = true

  def email
    self.guest_id
  end

  def email=(email : String?)
    self.guest_id = email
  end

  timestamps
end
