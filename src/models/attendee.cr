require "./event_metadata"
require "./guest"

class Attendee < Granite::Base
  connection pg
  table attendee

  column id : Int64, primary: true, auto: true

  belongs_to event : EventMetadata, primary_key: "id"
  belongs_to guest : Guest, primary_key: "email", foreign_key: email : String

  column checked_in : Bool = false
  column visit_expected : Bool = true
  timestamps
end
