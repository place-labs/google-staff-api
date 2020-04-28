require "./spec_helper"

describe EventMetadata do
  it "should save event metadata" do
    meta = EventMetadata.new
    meta.system_id = "sys_id"
    meta.event_id = "event1234"
    meta.host_email = "user@org.com"
    meta.resource_calendar = "resource@org.com"

    meta.event_start = Time.utc
    meta.event_end = 5.minutes.from_now
    meta.extension_data = JSON.parse("{}")

    result = meta.save
    result.should eq true
  end
end
