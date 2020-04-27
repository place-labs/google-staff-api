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
    user_name = google_user.name.fullName || "#{google_user.name.givenName} #{google_user.name.familyName}"

    if phones = google_user.phones.try(&.select(&.primary))
      phone = phones.first?.try(&.value) || google_user.recoveryPhone
    end

    if orgs = google_user.organizations.try(&.select(&.primary))
      department = orgs.first?.try &.department
    end

    if accounts = google_user.posixAccounts.try(&.select(&.primary))
      account = accounts.first?.try &.username
    end

    {
      name:       user_name,
      email:      google_user.primaryEmail,
      phone:      phone,
      department: department,
      photo:      google_user.thumbnailPhotoUrl,
      username:   account,
    }.to_h.compact
  end
end
