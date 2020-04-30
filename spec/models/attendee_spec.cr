require "../spec_helper"

describe Attendee do
  it "should save and destroy attendees" do
    meta = generate_event
    guest = generate_guest
    attend = guest.attendee_for(meta.id.not_nil!)

    begin
      find_attend = Attendee.find!(attend.id)
      find_attend.guest.id.should eq(guest.id)
      find_attend.email.should eq(guest.id)
      find_attend.event.id.should eq(meta.id)

      meta.destroy
      Attendee.find(attend.id).should eq(nil)
      guest.destroy
    rescue e
      meta.destroy
      guest.destroy
      raise e
    end
  end
end
