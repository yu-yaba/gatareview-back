# frozen_string_literal: true

module Rack
  class Attack
    AUTH_LIMIT = Integer(ENV.fetch('AUTH_RATE_LIMIT_PER_MINUTE', 10))
    API_LIMIT = Integer(ENV.fetch('API_RATE_LIMIT_PER_FIVE_MINUTES', 300))

    throttle('auth/google/ip', limit: AUTH_LIMIT, period: 1.minute) do |request|
      request.ip if request.post? && request.path == '/api/v1/auth/google'
    end

    throttle('api/ip', limit: API_LIMIT, period: 5.minutes) do |request|
      request.ip if request.path.start_with?('/api/')
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
