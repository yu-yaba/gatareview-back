class AuthorizeApiRequest
  MAX_AUTHORIZATION_HEADER_BYTES = 16 * 1024

  def initialize(headers = {})
    @headers = headers
  end

  def self.call(headers)
    new(headers).call
  end

  def call
    {
      result: user
    }
  end

  private

  attr_reader :headers

  def user
    return unless decoded_auth_token

    @user ||= User.find(decoded_auth_token[:user_id]).tap do |user|
      token_version = Integer(decoded_auth_token[:token_version], exception: false)
      return nil unless token_version == user.token_version
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def decoded_auth_token
    @decoded_auth_token ||= JsonWebToken.decode(http_auth_header)
  end

  def http_auth_header
    auth_header = headers['Authorization']

    unless auth_header.is_a?(String) && !auth_header.empty?
      log_auth_debug('No Authorization header found')
      return
    end

    token = auth_header[/\ABearer[ \t]+(\S+)\z/, 1] if auth_header.bytesize <= MAX_AUTHORIZATION_HEADER_BYTES
    if token
      log_auth_debug('Valid Bearer token extracted')
    else
      Rails.logger.warn "Invalid Authorization header format - must be 'Bearer <token>'"
    end
    token
  end

  def log_auth_debug(message)
    return unless Rails.env.development?

    Rails.logger.debug(message)
  end
end
