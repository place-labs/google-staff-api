require "uri"
require "../../models/user_jwt"

# Helper to grab user and authority from a request
module Utils::CurrentUser
  Log = ::App::Log.for("authorize!")

  @user_token : ::UserJWT?

  # Parses, and validates JWT if present.
  # Throws Error::MissingBearer and JWT::Error.
  def authorize!
    return if @user_token

    token = acquire_token

    # Request must have a bearer token
    raise Error::Unauthorized.new unless token

    begin
      @user_token = UserJWT.decode(token)
    rescue e : JWT::Error
      Log.warn(exception: e) { "bearer malformed: #{e.message}" }
      # Request bearer was malformed
      raise Error::Unauthorized.new "bearer malformed"
    end

    # Token and authority domains must match
    token_domain_host = URI.parse(user_token.domain).host.to_s
    authority_domain_host = URI.parse(request.host.as(String)).host.to_s
    unless token_domain_host == authority_domain_host
      ::Log.with_context do
        Log.context.set({token: token_domain_host, authority: authority_domain_host})
        Log.info { "domain does not match token's" }
      end
      raise Error::Unauthorized.new "domain does not match token's"
    end
  rescue e
    # ensure that the user token is nil if this function ever errors.
    @user_token = nil
    raise e
  end

  # Getter for user_token
  def user_token : UserJWT
    # FIXME: Remove when action-controller respects the ordering of route callbacks
    authorize! unless @user_token
    @user_token.as(UserJWT)
  end

  # Read admin status from supplied request JWT
  def check_admin
    raise Error::Forbidden.new unless is_admin?
  end

  # Read support status from supplied request JWT
  def check_support
    raise Error::Forbidden.new unless is_support?
  end

  def is_admin?
    user_token.is_admin?
  end

  def is_support?
    token = user_token
    token.is_support? || token.is_admin?
  end

  # Pull JWT from...
  # - Authorization header
  # - "bearer_token" param
  @access_token : String? = nil

  protected def acquire_token : String?
    token = @access_token
    return token if token
    @access_token = if (token = request.headers["Authorization"]?)
                      token = token.lchop("Bearer ").rstrip
                      token unless token.empty?
                    elsif (token = params["bearer_token"]?)
                      token.strip
                    end
  end
end
