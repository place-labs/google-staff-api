require "../spec_helper"

describe Booking do
  it "should save and destroy bookings" do
    booking = Booking.new
    booking.user_id = "user-1234"
    booking.user_email = "steve@bob.com"
    booking.user_name = "hello world"
    booking.asset_id = "asset-id"
    booking.booking_type = "desk"
    booking.title = "best desk"
    booking.zones = ["zone-1234", "zone-4567", "zone-890"]
    booking.booking_start = 5.minutes.from_now
    booking.booking_end = 40.minutes.from_now

    begin
      booking.save!
    rescue e
      puts booking.errors
      raise e
    end

    results = [] of Booking

    # Let's find this booking
    Booking.all(
      "WHERE ? = ANY (zones) AND ? = ANY (zones)",
      ["zone-4567", "zone-1234"]
    ).each { |book| results << book }

    results.map(&.id).includes?(booking.id).should eq(true)

    booking.destroy
  end

  it "should instantiate a booking using JSON" do
    booking = Booking.from_json(%({"user_email":"bob@jane.com","extension_data":{"test":"data"}}))
    booking.user_email.should eq("bob@jane.com")
    booking.extension_data.to_json.should eq(%({"test":"data"}))
  end
end
