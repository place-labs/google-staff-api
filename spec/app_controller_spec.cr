require "./spec_helper"

describe Calendars do
  systems_json = {{ read_file("#{__DIR__}/mocks/systems.json") }}
  systems_resp = Array(JSON::Any).from_json(systems_json).map &.to_json

  it "should generate a request ID string" do
    # instantiate the controller you wish to unit test
    app = Calendars.new(context("GET", "/", HEADERS))

    # Test the instance methods of the controller
    app.configure_request_logging.should contain("-")
  end

  it "should extract calendar ids from PlaceOS" do
    # Expects a Google request
    CalendarHelper.mock_token
    CalendarHelper.mock_calendar_list

    # Zone requests
    {"z1", "z2", "z3"}.each_with_index do |zone_id, index|
      WebMock
        .stub(:get, DOMAIN + "/api/engine/v2/systems")
        .with(query: {
          "limit"    => "1000",
          "offset"   => "0",
          "zone_id"  => zone_id,
          "capacity" => "2",
          "bookable" => "true",
        })
        .to_return(body: "[#{systems_resp[index]}]")
    end

    # System ID request
    {"sys-AAJQVPIR9Uf", "sys-rJQVPIR9Uf"}.each_with_index do |system_id, index|
      WebMock
        .stub(:get, DOMAIN + "/api/engine/v2/systems/#{system_id}")
        .to_return(body: systems_resp[3 - index])
    end

    # instantiate the controller for unit test
    systems = Calendars.new(context(
      "GET",
      "/api/staff/v1/calendars/availability?zone_ids=z1,z2,z3&system_ids=sys-AAJQVPIR9Uf,sys-rJQVPIR9Uf&capacity=2&bookable=true&calendars=cal1,cal2",
      HEADERS
    ))

    # Test the instance methods of the controller
    results = {} of String => String?
    systems.matching_calendar_ids.each { |cal, sys|
      results[cal] = sys.try &.id
    }
    results.should eq({
      "cal2"              => nil,
      "room1@example.com" => "sys-rJQQlR4Cn7",
      "room2@example.com" => "sys-rJQSySsELE",
      "room3@example.com" => "sys-rJQVPIR9Uf",
      # Returned by a system ID request
      "room4@example.com" => "sys-AAJQVPIR9Uf",
    })
  end

  # ==============
  # TODO:: Work out how to emulate this without actually making a real request
  # ==============
  # with_server do
  #  it "should welcome you" do
  #    result = curl("GET", "/")
  #    result.body.includes?("You're being trampled by Spider-Gazelle!").should eq(true)
  #  end
  # end
end
