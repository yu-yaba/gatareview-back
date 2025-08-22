class AuthorizeApiRequest
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
    @user ||= User.find(decoded_auth_token[:user_id]) if decoded_auth_token
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def decoded_auth_token
    @decoded_auth_token ||= JsonWebToken.decode(http_auth_header)
  end

  def http_auth_header
    auth_header = headers['Authorization']
    Rails.logger.info "Authorization header present: #{auth_header.present?}"
    
    if auth_header.present?
      # Bearer形式の厳密な検証
      if auth_header.match(/\ABearer\s+(.+)\z/)
        token = $1
        Rails.logger.info "Valid Bearer token extracted"
        return token
      else
        Rails.logger.warn "Invalid Authorization header format - must be 'Bearer <token>'"
        return nil
      end
    end
    
    Rails.logger.info "No Authorization header found"
    nil
  end
end