class Staff < Application
  base "/api/staff/v1/people"

  def index
    query = params["q"]?
    dir = google_directory
    render json: dir.users(query).users.map { |u| build_user(u) }
  end

  def show
    # TODO:: return user location information
    user_info = google_directory.lookup(params["id"])
    render json: build_user(user_info)
  end

  def build_user(google_user) : Hash(Symbol, String)
    user_name = google_user.name.full_name || "#{google_user.name.given_name} #{google_user.name.family_name}"

    if phones = google_user.phones.try(&.select(&.primary))
      phone = phones.first?.try(&.value) || google_user.recovery_phone
    end

    if orgs = google_user.organizations.try(&.select(&.primary))
      department = orgs.first?.try &.department
    end

    if accounts = google_user.posix_accounts.try(&.select(&.primary))
      account = accounts.first?.try &.username
    end

    {
      name:       user_name,
      email:      google_user.primary_email,
      phone:      phone,
      department: department,
      photo:      google_user.thumbnail_photo_url,
      username:   account,
    }.to_h.compact
  end
end
