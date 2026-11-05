# frozen_string_literal: true

# Heroku's router only vouches for X-Forwarded-For. Forwarded and Client-Ip
# arrive straight from the client, and RateLimitDiscriminator already ignores
# them. Drop them before ActionDispatch::RemoteIp so Rails' remote_ip (used in
# request logs) cannot be steered by them, and so a client sending conflicting
# headers cannot make every request fail with IpSpoofAttackError.
class StripUntrustedForwardingHeaders
  HEADERS = %w[HTTP_FORWARDED HTTP_CLIENT_IP].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    HEADERS.each { |header| env.delete(header) }
    @app.call(env)
  end
end

Rails.application.config.middleware.insert_before ActionDispatch::RemoteIp, StripUntrustedForwardingHeaders
