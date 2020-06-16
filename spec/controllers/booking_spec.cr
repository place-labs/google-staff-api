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
      zones.each { |zone| str << " AND ? = ANY (zones)" }
    end

    Booking.all(
      "WHERE booking_start <= ? AND booking_end >= ? AND booking_type = ?#{query}",
      [ending, starting, "desk"] + zones
    ).each { |booking| results << booking }

    results.size.should eq(2)
  end

  it "should return a list of bookings" do
    # instantiate the controller
    response = IO::Memory.new

    starting = 5.minutes.from_now.to_unix
    ending = 40.minutes.from_now.to_unix
    route = "/api/staff/v1/bookings?period_start=#{starting}&period_end=#{ending}&type=desk"
    app = Bookings.new(context("GET", route, HEADERS, response_io: response))

    # Test the instance method of the controller
    app.index
    data = response.to_s
    data = JSON.parse(data.split("\r\n").reject(&.empty?)[-1])
    data.as_a.size.should eq(2)
  end
end
