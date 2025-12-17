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

    # セキュリティ/ノイズ対策: 本番環境では認証ヘッダーの詳細ログを出さない
    log_auth_debug("Authorization header present: #{auth_header.present?}")

    if auth_header.present?
      # Bearer形式の厳密な検証
      match = auth_header.match(/\ABearer\s+(.+)\z/)
      if match
        log_auth_debug('Valid Bearer token extracted')
        return match[1]
      else
        Rails.logger.warn "Invalid Authorization header format - must be 'Bearer <token>'"
        return nil
      end
    end

    log_auth_debug('No Authorization header found')
    nil
  end

  def log_auth_debug(message)
    return unless Rails.env.development?

    Rails.logger.debug(message)
  end
end
