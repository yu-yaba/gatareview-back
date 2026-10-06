# frozen_string_literal: true

class JsonWebToken
  ConfigurationError = Class.new(StandardError)
  MINIMUM_SECRET_BYTES = 32
  ISSUED_AT_CLOCK_SKEW_SECONDS = 30

  def self.secret_key(environment: Rails.env, configured_secret: ENV['JWT_SECRET_KEY'] || Rails.application.credentials.jwt_secret_key)
    if configured_secret.blank?
      raise ConfigurationError, 'JWT_SECRET_KEY に32バイト以上のランダムな専用鍵を設定してください' unless %w[development test].include?(environment.to_s)

      return Rails.application.key_generator.generate_key("gatareview-jwt-#{environment}", MINIMUM_SECRET_BYTES).unpack1('H*')
    end

    raise ConfigurationError, 'JWT_SECRET_KEY は32バイト以上必要です' if configured_secret.bytesize < MINIMUM_SECRET_BYTES

    configured_secret
  end

  def self.encode(payload, exp = 30.days.from_now)
    payload[:exp] = exp.to_i
    payload[:iat] = Time.current.to_i # 発行時刻を追加
    JWT.encode(payload, secret_key, 'HS256')
  end

  def self.decode(token)
    return nil unless token.is_a?(String) && token.present?

    decoded = JWT.decode(token, secret_key, true, {
                           algorithm: 'HS256', required_claims: %w[user_id token_version exp iat]
                         })[0]
    return nil unless valid_authentication_claims?(decoded)

    HashWithIndifferentAccess.new(decoded)
  rescue JWT::ExpiredSignature => e
    Rails.logger.warn "JWT expired: #{e.class}"
    nil
  rescue JWT::DecodeError => e
    Rails.logger.error "JWT decode rejected: #{e.class}"
    nil
  end

  def self.valid_token?(token)
    !decode(token).nil?
  end

  def self.valid_authentication_claims?(claims)
    return false unless claims.is_a?(Hash)
    return false unless %w[user_id token_version exp iat].all? { |key| claims[key].is_a?(Integer) }

    claims['user_id'].positive? && claims['token_version'] >= 0 && claims['exp'].positive? &&
      claims['iat'] >= 0 && claims['iat'] <= Time.current.to_i + ISSUED_AT_CLOCK_SKEW_SECONDS
  end
  private_class_method :valid_authentication_claims?
end
