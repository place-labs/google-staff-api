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

  it "should instantiate a guest using JSON" do
    guest = Guest.from_json(%({"email":"bob@jane.com","banned":true,"extension_data":{"test":"data"}}))
    guest.email.should eq("bob@jane.com")
    guest.banned.should eq(true)
    guest.extension_data.to_json.should eq(%({"test":"data"}))
  end
end
