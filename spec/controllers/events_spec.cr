require "../spec_helper"

describe Events do
  systems_json = {{ read_file("#{__DIR__}/../mocks/systems.json") }}
  systems_resp = Array(JSON::Any).from_json(systems_json).map &.to_json

  it "should return a list of events" do
    CalendarHelper.mock_token

    WebMock
      .stub(:get, DOMAIN + "/api/engine/v2/systems")
      .with(query: {
        "limit"   => "1000",
        "offset"  => "0",
        "zone_id" => "z1",
      })
      .to_return(body: "[#{systems_resp[1]}]")

    WebMock.stub(:get, "https://www.googleapis.com/calendar/v3/calendars/room2@example.com/events?maxResults=2500&singleEvents=true&timeMin=2020-05-02T08:20:45Z&timeMax=2020-05-02T12:21:37Z&showDeleted=false")
      .to_return(body: CalendarHelper.events_response.to_json)

    now = 1588407645
    later = 1588422097

    # instantiate the controller
    ctx = context(
      "GET",
      "/api/staff/v1/events?zone_ids=z1&period_start=#{now}&period_end=#{later}",
      HEADERS
    )
    ctx.response.output = IO::Memory.new
    Events.new(ctx).index

    # Test the instance method of the controller
    ctx.response.output.to_s.should start_with(
      "[{\"id\":\"123456789\",\"status\":null,\"calendar\":\"room2@example.com\",\"title\":null,\"body\":null,\"location\":null,\"host\":null,\"creator\":\"test@example.com\",\"private\":false,\"event_start\""
    )
  end

  it "should return a list of events with metadata" do
    CalendarHelper.mock_token

    WebMock
      .stub(:get, DOMAIN + "/api/engine/v2/systems")
      .with(query: {
        "limit"   => "1000",
        "offset"  => "0",
        "zone_id" => "z1",
      })
      .to_return(body: "[#{systems_resp[1]}]")

    WebMock.stub(:get, "https://www.googleapis.com/calendar/v3/calendars/room2@example.com/events?maxResults=2500&singleEvents=true&timeMin=2020-05-02T08:20:45Z&timeMax=2020-05-02T12:21:37Z&showDeleted=false")
      .to_return(body: CalendarHelper.events_response.to_json)

    now = 1588407645
    later = 1588422097

    # create some metadata that we want mixed in
    meta = EventMetadata.new
    meta.system_id = "sys_id"
    meta.event_id = "123456789"
    meta.host_email = "user@org.com"
    meta.resource_calendar = "room2@example.com"
    meta.event_start = Time.utc.to_unix
    meta.event_end = 5.minutes.from_now.to_unix
    meta.extension_data = JSON.parse(%(
      {
        "breakdown": 15,
        "cleaned": false
      }
    ))
    result = meta.save
    result.should eq true

    # instantiate the controller
    ctx = context(
      "GET",
      "/api/staff/v1/events?zone_ids=z1&period_start=#{now}&period_end=#{later}",
      HEADERS
    )
    ctx.response.output = IO::Memory.new
    Events.new(ctx).index

    # Test the instance method of the controller
    ctx.response.output.to_s.includes?(%({"breakdown":15,"cleaned":false})).should eq(true)
  end
end
