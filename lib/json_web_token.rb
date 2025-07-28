class JsonWebToken
  # セキュリティ強化: JWT専用の秘密鍵を使用
  SECRET_KEY = ENV['JWT_SECRET_KEY'] || 
               Rails.application.credentials.jwt_secret_key ||
               Rails.application.credentials.secret_key_base || 
               ENV['RAILS_SECRET_KEY_BASE'] || 
               raise('JWT_SECRET_KEY が設定されていません。JWT専用の秘密鍵を設定してください')

  def self.encode(payload, exp = 30.days.from_now)
    payload[:exp] = exp.to_i
    payload[:iat] = Time.current.to_i # 発行時刻を追加
    JWT.encode(payload, SECRET_KEY, 'HS256')
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY, true, { algorithm: 'HS256' })[0]
    HashWithIndifferentAccess.new(decoded)
  rescue JWT::ExpiredSignature => e
    Rails.logger.warn "JWT expired: #{e.message}"
    nil
  rescue JWT::DecodeError => e
    Rails.logger.error "JWT decode error: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "JWT unexpected error: #{e.message}"
    nil
  end

  def self.valid_token?(token)
    !decode(token).nil?
  end
end