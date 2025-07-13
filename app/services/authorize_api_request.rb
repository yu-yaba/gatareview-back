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
    @user ||= User.find(decoded_auth_token[:id]) if decoded_auth_token
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def decoded_auth_token
    @decoded_auth_token ||= JsonWebToken.decode(http_auth_header)
  end

  def http_auth_header
    auth_header = headers['Authorization']
    Rails.logger.info "Authorization header present: #{auth_header.present?}"
    Rails.logger.info "Raw Authorization header: #{auth_header}"
    
    if auth_header.present?
      token = auth_header.split(' ').last
      Rails.logger.info "Extracted token: #{token[0..20]}..." if token
      return token
    end
    
    Rails.logger.info "No Authorization header found"
    nil
  end
end