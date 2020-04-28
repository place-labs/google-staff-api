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
        Attendee.all(
          "WHERE event_id IN (SELECT id FROM metadata WHERE event_start <= ? AND event_end >= ? AND system_id IN ?)",
          [ending, starting, system_ids]
        ).each { |attendee| attendees[attendee.email] = attendee }
      else
        Attendee.all(
          "WHERE event_id IN (SELECT id FROM metadata WHERE event_start <= ? AND event_end >= ?)",
          [ending, starting]
        ).each { |attendee| attendees[attendee.email] = attendee }
      end

      guests = {} of String => Guest
      Guest.where(:id, :in, attendees.keys).each { |guest| guests[guest.id.not_nil!] = guest }

      render json: attendees.each { |email, visitor| attending_guest(visitor, guests[email]?) }
    elsif query.empty?
      # Return the first 1000 guests
      render json: Guest.order(:name).limit(1500).map { |g| g }
    else
      # Return guests based on the filter query
      query = "%#{query}%"
      render json: Guest.all("WHERE searchable LIKE ? LIMIT 1500", [query]).map { |g| g }
    end
  end

  def show
    # TODO:: find out if they are attending today
    render json: current_guest
  end

  def update
    guest = current_guest
    changes = Guest.from_json(request.body.as(IO))
    {% for key in [:name, :preferred_name, :phone, :organisation, :notes, :photo, :banned, :dangerous, :extension_data] %}
      guest.{{key.id}} = changes.{{key.id}} if changes.{{key.id}}
    {% end %}
    save_and_respond guest, create: false
  end

  put "/:id", :update_alt { update }

  def create
    save_and_respond Guest.from_json(request.body.as(IO)), create: true
  end

  def destroy
    current_guest.destroy
    head :accepted
  end

  get("/:id/meetings", :meetings) do
    time = Time.utc
    render json: current_guest.events.reject { |event| event.event_end > time }
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
