require "../spec_helper"

describe Bookings do
  booking1 = Booking.new
  booking2 = Booking.new

  Spec.before_each do
    booking1 = Booking.new
    booking1.user_id = "user-1234"
    booking1.user_email = "steve@bob.com"
    booking1.user_name = "hello world"
    booking1.asset_id = "asset-id"
    booking1.booking_type = "desk"
    booking1.title = "best desk"
    booking1.zones = ["zone-1234", "zone-4567", "zone-890"]
    booking1.booking_start = 5.minutes.from_now.to_unix
    booking1.booking_end = 1.hour.from_now.to_unix
    booking1.save!

    booking2 = Booking.new
    booking2.user_id = "user-5678"
    booking2.user_email = "jon@bob.com"
    booking2.user_name = "jon dogg"
    booking2.asset_id = "asset-no2"
    booking2.booking_type = "desk"
    booking2.title = "another desk"
    booking2.zones = ["zone-4127", "zone-890"]
    booking2.booking_start = 5.minutes.from_now.to_unix
    booking2.booking_end = 30.minutes.from_now.to_unix
    booking2.save!
  end

  Spec.after_each do
    booking1.destroy
    booking2.destroy
  end

  it "should find the bookings" do
    starting = 5.minutes.from_now.to_unix
    ending = 40.minutes.from_now.to_unix
    zones = [] of String
    results = [] of Booking

    query = String.build do |str|
      zones.each { |_zone| str << " AND ? = ANY (zones)" }
    end

    Booking.all(
      "WHERE booking_start <= ? AND booking_end >= ? AND booking_type = ?#{query}",
      [ending, starting, "desk"] + zones
    ).each { |booking| results << booking }

    results.size.should eq(2)
  end

  it "should return a list of bookings" do
    # instantiate the controller
    starting = 5.minutes.from_now.to_unix
    ending = 40.minutes.from_now.to_unix
    route = "/api/staff/v1/bookings?period_start=#{starting}&period_end=#{ending}&type=desk"
    ctx = context("GET", route, HEADERS)
    ctx.response.output = IO::Memory.new
    Bookings.new(ctx).index

    # Test the instance method of the controller
    data = begin
      JSON.parse(ctx.response.output.to_s)
    rescue
      nil
    end

    data.as_a.size.should eq(2)

    # filter by zones
    route = "/api/staff/v1/bookings?period_start=#{starting}&period_end=#{ending}&type=desk&zones=zone-890,zone-4127"
    ctx = context("GET", route, HEADERS)
    ctx.response.output = IO::Memory.new
    Bookings.new(ctx).index

    data = begin
      JSON.parse(ctx.response.output.to_s)
    rescue
      nil
    end

    data.as_a.size.should eq(1)
  end

  it "should delete a booking" do
    # instantiate the controller
    context = context("DELETE", "/api/staff/v1/bookings/#{booking2.id}/", HEADERS)
    context.route_params = {"id" => booking2.id.not_nil!.to_s}
    app = Bookings.new(context)

    WebMock.stub(:post, "https://example.place.technology/api/engine/v2/signal").to_return(body: "")

    # Test the instance method of the controller
    app.destroy

    # Check only one is returned
    starting = 5.minutes.from_now.to_unix
    ending = 40.minutes.from_now.to_unix
    route = "/api/staff/v1/bookings?period_start=#{starting}&period_end=#{ending}&type=desk"
    ctx = context("GET", route, HEADERS)
    ctx.response.output = IO::Memory.new
    Bookings.new(ctx).index

    data = begin
      JSON.parse(ctx.response.output.to_s)
    rescue
      nil
    end
    data.as_a.size.should eq(1)
  end

  it "should create and update a booking" do
    starting = 5.minutes.from_now.to_unix
    ending = 40.minutes.from_now.to_unix

    # instantiate the controller
    body = IO::Memory.new
    body << %({"asset_id":"some_desk","booking_start":#{starting},"booking_end":#{ending},"booking_type":"desk"})
    body.rewind
    ctx = context("POST", "/api/staff/v1/bookings/", HEADERS, body)
    ctx.response.output = IO::Memory.new
    Bookings.new(ctx).create

    WebMock.stub(:post, "https://example.place.technology/api/engine/v2/signal").to_return(body: "")

    created = begin
      Booking.from_json(ctx.response.output.to_s)
    rescue
      nil
    end

    created.asset_id.should eq("some_desk")
    created.booking_start.should eq(starting)
    created.booking_end.should eq(ending)

    # instantiate the controller
    body = IO::Memory.new
    body << %({"extension_data":{"other":"stuff"}})
    body.rewind
    ctx = context("PATCH", "/api/staff/v1/bookings/#{created.id}", HEADERS, body)
    ctx.route_params = {"id" => created.id.to_s}
    ctx.response.output = IO::Memory.new
    Bookings.new(ctx).update

    updated = begin
      Booking.from_json(ctx.response.output.to_s)
    rescue
      nil
    end

    updated.extension_data["other"].should eq("stuff")
  end
end
