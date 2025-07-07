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
    if headers['Authorization'].present?
      return headers['Authorization'].split(' ').last
    end
    nil
  end
end