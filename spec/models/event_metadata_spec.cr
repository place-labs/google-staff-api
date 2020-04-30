require "../spec_helper"

describe EventMetadata do
  it "should save event metadata" do
    meta = generate_event
    meta.extension_data = JSON.parse(%(
      {
        "testing": ["some", "json", "data"],
        "working": 1234
      }
    ))

    result = meta.save
    result.should eq true

    meta_lookup = EventMetadata.find!("sys_id-event1234")
    meta_lookup.extension_data.should eq(JSON.parse(%(
      {
        "testing": ["some", "json", "data"],
        "working": 1234
      }
    )))

    meta_lookup.destroy
  end

  it "should be able to locate attendees in this meeting" do
    meta = generate_event

    attend = Attendee.new
    attend.email = "bob@org.com"
    attend.event = meta
    result = attend.save
    result.should eq true

    meta.attendees.map(&.id).should eq([attend.id])
    meta.destroy
  end
end
