class Guests < Application
  base "/api/staff/v1/guests"

  before_action :find_guest, only: [:show, :update, :update_alt, :destroy, :meetings]
  getter guest : Guest?

  def index
    query = (query_params["q"]? || "").gsub(/[^\w\s]/, "").strip.downcase
    period_start = query_params["period_start"]?
    if period_start
      starting = period_start.to_i64
      ending = query_params["period_end"].to_i64

      # Return the guests visiting today
      attendees = {} of String => Attendee

      # We want a subset of the calendars
      if query_params["zone_ids"]? || query_params["system_ids"]?
        system_ids = matching_calendar_ids.values.map(&.try(&.id))
        render(json: [] of Nil) if system_ids.empty?

        Attendee.all(
          "WHERE event_id IN (SELECT id FROM metadata WHERE event_start <= ? AND event_end >= ? AND system_id IN ('#{system_ids.join(%(','))}'))",
          [ending, starting]
        ).each { |attendee| attendees[attendee.email] = attendee }
      else
        query = Attendee.all(
          "WHERE event_id IN (SELECT id FROM metadata WHERE event_start <= ? AND event_end >= ?)",
          [ending, starting]
        ).each { |attendee| attendees[attendee.email] = attendee }
      end

      render(json: [] of Nil) if attendees.empty?

      guests = {} of String => Guest
      Guest.where(:email, :in, attendees.keys).each { |guest| guests[guest.email.not_nil!] = guest }

      render json: attendees.map { |email, visitor| attending_guest(visitor, guests[email]?) }
    elsif query.empty?
      # Return the first 1000 guests
      render json: Guest.order(:name).limit(1500).map { |g| attending_guest(nil, g) }
    else
      # Return guests based on the filter query
      query = "%#{query}%"
      render json: Guest.all("WHERE searchable LIKE ? LIMIT 1500", [query]).map { |g| attending_guest(nil, g) }
    end
  end

  def show
    # find out if they are attending today
    guest = current_guest
    attendee = guest.attending_today?(get_timezone)
    render json: attending_guest(attendee, guest)
  end

  def update
    guest = current_guest
    changes = Guest.from_json(request.body.as(IO))
    {% for key in [:name, :preferred_name, :phone, :organisation, :notes, :photo, :banned, :dangerous] %}
      guest.{{key.id}} = changes.{{key.id}}
    {% end %}

    # merge changes into extension data
    data = guest.extension_data.as_h
    changes.extension_data.as_h.each { |key, value| data[key] = value }
    guest.extension_data = nil
    guest.ext_data = data.to_json

    if guest.save
      attendee = guest.attending_today?(get_timezone)
      render json: attending_guest(attendee, guest), status: HTTP::Status::OK
    else
      render json: guest.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  put "/:id", :update_alt { update }

  def create
    guest = Guest.from_json(request.body.as(IO))
    if guest.save
      attendee = guest.attending_today?(get_timezone)
      render json: attending_guest(attendee, guest), status: HTTP::Status::CREATED
    else
      render json: guest.errors.map(&.to_s), status: :unprocessable_entity
    end
  end

  def destroy
    current_guest.destroy
    head :accepted
  end

  get("/:id/meetings", :meetings) do
    future_only = query_params["include_past"]? != "true"
    limit = (query_params["limit"]? || "10").to_i

    placeos_client = get_placeos_client.systems
    calendar = calendar_for(user_token.user.email)

    events = Promise.all(current_guest.events(future_only, limit).map { |metadata|
      Promise.defer {
        cal_id = metadata.resource_calendar.not_nil!
        system = placeos_client.fetch(metadata.system_id.not_nil!)
        event = calendar.event(metadata.event_id.not_nil!, cal_id)
        if event
          standard_event(cal_id, system, event, metadata)
        else
          nil
        end
      }
    }).get.compact
    render json: events
  end

  # ============================================
  #              Helper Methods
  # ============================================

  def current_guest : Guest
    @guest || find_guest
  end

  def find_guest
    id = route_params["id"]
    # Find will raise a 404 (not found) if there is an error
    @guest = Guest.find!(id)
  end
end
