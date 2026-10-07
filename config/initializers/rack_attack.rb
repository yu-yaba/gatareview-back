# frozen_string_literal: true

require 'ipaddr'

module RateLimitDiscriminator
  module_function

  # Heroku appends the router-observed address to X-Forwarded-For. Other
  # deployments use the socket address until their proxy contract is configured.
  # Rack's `ip` and Rails' `remote_ip` prefer unverified Forwarded headers.
  def client_ip(request, heroku: ENV['DYNO'].present?)
    socket_address = normalized_ip(request.get_header('REMOTE_ADDR'))
    return socket_address || 'unknown' unless heroku

    observed_address = request.get_header('HTTP_X_FORWARDED_FOR').to_s.split(',', -1).last.to_s.strip
    normalized_ip(observed_address) || socket_address || 'unknown'
  end

  def normalized_ip(value)
    return if value.blank? || value.include?('/')

    IPAddr.new(value).to_s
  rescue IPAddr::InvalidAddressError
    nil
  end
end

module Rack
  class Attack
    AUTH_LIMIT = Integer(ENV.fetch('AUTH_RATE_LIMIT_PER_MINUTE', 10))
    API_LIMIT = Integer(ENV.fetch('API_RATE_LIMIT_PER_FIVE_MINUTES', 300))
    GOOGLE_AUTH_PATH_PATTERN = %r{\A/api/v1/auth/google(?:\.[^/]+)?/?\z}

    throttle('auth/google/ip', limit: AUTH_LIMIT, period: 1.minute) do |request|
      RateLimitDiscriminator.client_ip(request) if request.post? && request.path.match?(GOOGLE_AUTH_PATH_PATTERN)
    end

    throttle('api/ip', limit: API_LIMIT, period: 5.minutes) do |request|
      RateLimitDiscriminator.client_ip(request) if request.path.start_with?('/api/')
    end

    self.throttled_responder = lambda do |request|
      match_data = request.env.fetch('rack.attack.match_data', {})
      period = match_data.fetch(:period, 60).to_i
      retry_after = period - (Time.now.to_i % period)

      [
        429,
        {
          'Content-Type' => 'application/json',
          'Retry-After' => retry_after.to_s
        },
        [{ error: 'リクエストが多すぎます。しばらく待ってから再試行してください' }.to_json]
      ]
    end
  end
end
