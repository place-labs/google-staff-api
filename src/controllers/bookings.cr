class Bookings < Application
  base "/api/staff/v1/bookings"

  before_action :find_booking, only: [:show, :update, :update_alt, :destroy]
  before_action :check_access, only: [:update, :update_alt, :destroy]
  getter booking : Booking?

  def index
    starting = Time.unix(query_params["period_start"].to_i64)
    ending = Time.unix(query_params["period_end"].to_i64)
    booking_type = query_params["type"]
    zones = Set.new((query_params["zones"]? || "").split(',').map(&.strip).reject(&.empty?)).to_a

    results = [] of Booking

    # Bookings have the requested zones
    # https://www.postgresql.org/docs/9.1/arrays.html#ARRAYS-SEARCHING
    query = String.build do |str|
      zones.each { |zone| str << " AND ? = ANY (zones)" }
    end

    Booking.all(
      "WHERE booking_start <= ? AND booking_end >= ? AND booking_type = ?#{query}",
      [ending, starting, booking_type] + zones
    ).each { |booking| results << booking }

    render json: results
  end

  def create
    booking = Booking.from_json(request.body.as(IO))

    # TODO:: check there isn't a clashing booking

    # Add the user details
    user = user_token.user
    booking.user_id = user_token.id
    booking.user_email = user.email
    booking.user_name = user.name

    if booking.save
      spawn do
        get_placeos_client.root.signal("staff/booking/changed", {
          action:       :create,
          id:           booking.id,
          booking_type: booking.booking_type,
          resource:     booking.asset_id,
        })
      end

      render json: booking, status: HTTP::Status::CREATED
    else
      render json: booking.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  def update
    booking = current_booking
    changes = Booking.from_json(request.body.as(IO))

    {% for key in [:asset_id, :booking_start, :booking_end, :title, :description] %}
      booking.{{key.id}} = changes.{{key.id}}
    {% end %}

    # merge changes into extension data
    data = booking.extension_data.as_h
    changes.extension_data.as_h.each { |key, value| data[key] = value }
    booking.extension_data = nil
    booking.ext_data = data.to_json

    # TODO:: check there isn't a clashing booking

    if booking.save
      spawn do
        get_placeos_client.root.signal("staff/booking/changed", {
          action:       :update,
          id:           booking.id,
          booking_type: booking.booking_type,
          resource:     booking.asset_id,
        })
      end

      render json: booking
    else
      render json: booking.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  put "/:id", :update_alt { update }

  def show
    render json: current_booking
  end

  def destroy
    booking = current_booking
    booking.destroy

    spawn do
      get_placeos_client.root.signal("staff/booking/changed", {
        action:       :cancelled,
        id:           booking.id,
        booking_type: booking.booking_type,
        resource:     booking.asset_id,
      })
    end

    head :accepted
  end

  # ============================================
  #              Helper Methods
  # ============================================

  def current_booking : Booking
    @booking || find_booking
  end

  def find_booking
    id = route_params["id"]
    # Find will raise a 404 (not found) if there is an error
    @booking = Booking.find!(id)
  end

  def check_access
    user = user_token
    if current_booking.user_id != user.id
      head :forbidden unless user.is_admin? || user.is_support?
    end
  end
end
