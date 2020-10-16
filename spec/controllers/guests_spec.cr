require "../spec_helper"

describe Guests do
  guest1 = Guest.new
  guest2 = Guest.new

  Spec.before_each do
    guest1 = Guest.new
    guest1.name = "Steve"
    guest1.email = "steve@place.techn"
    guest1.save

    guest2 = Guest.new
    guest2.name = "Jon"
    guest2.email = "jon@place.techn"
    guest2.save
  end

  Spec.after_each do
    guest1.destroy
    guest2.destroy
  end

  it "should return a list of guests" do
    # instantiate the controller
    ctx = context("GET", "/api/staff/v1/guests", HEADERS)
    ctx.response.output = IO::Memory.new
    Guests.new(ctx).index

    # Test the instance method of the controller
    ctx.response.output.to_s.should eq(
      %([{"email":"jon@place.techn","name":"Jon","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":false},{"email":"steve@place.techn","name":"Steve","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":false}])
    )
  end

  it "should return a filtered list of guests" do
    # instantiate the controller
    ctx = context("GET", "/api/staff/v1/guests?q=stev", HEADERS)
    ctx.response.output = IO::Memory.new
    Guests.new(ctx).index

    # Test the instance method of the controller
    ctx.response.output.to_s.should eq(
      %([{"email":"steve@place.techn","name":"Steve","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":false}])
    )
  end

  it "should return guests visiting today" do
    now = Time.utc.to_unix
    later = 4.hours.from_now.to_unix
    route = "/api/staff/v1/guests?period_start=#{now}&period_end=#{later}"
    ctx = context("GET", route, HEADERS)
    ctx.response.output = IO::Memory.new
    Guests.new(ctx).index

    # Test the instance method of the controller
    ctx.response.output.to_s.should eq("[]")

    meta = generate_event
    guest = generate_guest
    guest.attendee_for(meta.id.not_nil!)

    # instantiate the controller
    ctx2 = context("GET", route, HEADERS)
    ctx2.response.output = IO::Memory.new
    app = Guests.new(ctx2)

    begin
      # Test the instance method of the controller
      app.index
      ctx2.response.output.to_s.should eq(
        "[{\"email\":\"bob@outside.com\",\"name\":null,\"preferred_name\":null,\"phone\":null,\"organisation\":null,\"notes\":null,\"photo\":null,\"banned\":false,\"dangerous\":false,\"extension_data\":{},\"checked_in\":false,\"visit_expected\":true}]"
      )
    ensure
      meta.destroy
      guest.destroy
    end
  end

  systems_json = {{ read_file("#{__DIR__}/../mocks/systems.json") }}
  systems_resp = Array(JSON::Any).from_json(systems_json).map &.to_json

  it "should return guests visiting today in a subset of rooms" do
    meta = generate_event
    guest = generate_guest
    guest.attendee_for(meta.id.not_nil!)

    begin
      {"sys-rJQQlR4Cn7", "sys_id"}.each_with_index do |system_id, index|
        WebMock
          .stub(:get, DOMAIN + "/api/engine/v2/systems/#{system_id}")
          .to_return(body: systems_resp[index])
      end

      now = Time.utc.to_unix
      later = 4.hours.from_now.to_unix
      route = "/api/staff/v1/guests?period_start=#{now}&period_end=#{later}&system_ids=sys-rJQQlR4Cn7"

      ctx = context("GET", route, HEADERS)
      ctx.response.output = IO::Memory.new
      Guests.new(ctx).index

      # Test the instance method of the controller
      ctx.response.output.to_s.should eq("[]")

      # instantiate the controller

      route = "/api/staff/v1/guests?period_start=#{now}&period_end=#{later}&system_ids=sys-rJQQlR4Cn7,sys_id"
      ctx = context("GET", route, HEADERS)
      ctx.response.output = IO::Memory.new
      Guests.new(ctx).index

      # Test the instance method of the controller
      ctx.response.output.to_s.should eq(
        "[{\"email\":\"bob@outside.com\",\"name\":null,\"preferred_name\":null,\"phone\":null,\"organisation\":null,\"notes\":null,\"photo\":null,\"banned\":false,\"dangerous\":false,\"extension_data\":{},\"checked_in\":false,\"visit_expected\":true}]"
      )
    ensure
      meta.destroy
      guest.destroy
    end
  end

  it "should show a guests details" do
    # instantiate the controller
    ctx = context("GET", "/api/staff/v1/guests/#{guest1.email}/", HEADERS)
    ctx.route_params = {"id" => guest1.email.not_nil!}
    ctx.response.output = IO::Memory.new
    Guests.new(ctx).show

    # Test the instance method of the controller
    ctx.response.output.to_s.should eq(
      %({"email":"steve@place.techn","name":"Steve","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":false})
    )
  end

  it "should show a guests details when visiting today" do
    # instantiate the controller
    ctx = context("GET", "/api/staff/v1/guests/#{guest1.email}/", HEADERS)
    ctx.route_params = {"id" => guest1.email.not_nil!}
    ctx.response.output = IO::Memory.new
    app = Guests.new(ctx)

    meta = generate_event
    guest1.attendee_for(meta.id.not_nil!)

    # Test the instance method of the controller
    app.show
    ctx.response.output.to_s.should eq(
      %({"email":"steve@place.techn","name":"Steve","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":true})
    )
  end

  it "should delete a guest" do
    # instantiate the controller
    ctx = context("DELETE", "/api/staff/v1/guests/#{guest1.email}/", HEADERS)
    ctx.route_params = {"id" => guest1.email.not_nil!}

    # Test the instance method of the controller
    Guests.new(ctx).destroy

    # Check only one is returned
    ctx = context("GET", "/api/staff/v1/guests", HEADERS)
    ctx.response.output = IO::Memory.new

    # Test the instance method of the controller
    Guests.new(ctx).index
    ctx.response.output.to_s.should eq(
      %([{"email":"jon@place.techn","name":"Jon","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{},"checked_in":false,"visit_expected":false}])
    )
  end

  it "should create and update a guest" do
    # instantiate the controller
    body = IO::Memory.new
    body << %({"email":"bob@jane.com","banned":true,"extension_data":{"test":"data"}})
    body.rewind
    ctx = context("POST", "/api/staff/v1/guests/", HEADERS, body)
    ctx.response.output = IO::Memory.new
    Guests.new(ctx).create

    ctx.response.output.to_s.should eq(
      %({"email":"bob@jane.com","name":null,"preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":true,"dangerous":false,"extension_data":{"test":"data"},"checked_in":false,"visit_expected":false})
    )

    # instantiate the controller
    body = IO::Memory.new
    body << %({"name":"Bob Jane","extension_data":{"other":"stuff"}})
    body.rewind
    ctx = context("PATCH", "/api/staff/v1/guests/bob@jane.com", HEADERS, body)
    ctx.route_params = {"id" => "bob@jane.com"}
    ctx.response.output = IO::Memory.new
    Guests.new(ctx).update

    ctx.response.output.to_s.should eq(
      %({"email":"bob@jane.com","name":"Bob Jane","preferred_name":null,"phone":null,"organisation":null,"notes":null,"photo":null,"banned":false,"dangerous":false,"extension_data":{"test":"data","other":"stuff"},"checked_in":false,"visit_expected":false})
    )
  end
end
