require "../spec_helper"

describe Guest do
  it "should save and destroy guests" do
    meta = generate_event
    guest = generate_guest
    attend = guest.attendee_for(meta.id.not_nil!)

    begin
      guest.attendees.map(&.id).should eq([attend.id])
      guest.events.map(&.id).should eq([meta.id])
      guest.events(false).map(&.id).should eq([meta.id])

      guest.destroy
      Attendee.find(attend.id).should eq(nil)
      meta.destroy
    rescue e
      meta.destroy
      guest.destroy
      raise e
    end
  end
end
