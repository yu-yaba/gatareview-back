# frozen_string_literal: true

# Heroku's router only vouches for X-Forwarded-For. Forwarded and Client-Ip
# arrive straight from the client, and RateLimitDiscriminator already ignores
# them. Drop them at the very top of the middleware stack, before
# ActionDispatch::HostAuthorization, ActionDispatch::SSL and
# ActionDispatch::RemoteIp read them, so that:
# - Rails' remote_ip (used in request logs) cannot be steered by them,
# - Rack cannot derive the request scheme or host from a client-supplied
#   `Forwarded: proto=...;host=...` (e.g. `proto=http` would otherwise make
#   force_ssl answer with a 301), and
# - a client sending conflicting headers cannot make every request fail with
#   IpSpoofAttackError.
#
# Rails' ip_spoofing_check only compares these two headers against
# X-Forwarded-For, so with them removed it never fires. Client IP decisions
# (rate limiting, reCAPTCHA) are made by RateLimitDiscriminator, not by
# remote_ip. If the app moves behind a proxy that sets Forwarded itself,
# revisit this middleware together with RateLimitDiscriminator.
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

# Index 0 is also used by config/initializers/cors.rb; this file loads later, so
# it ends up in front of Rack::Cors as well.
Rails.application.config.middleware.insert_before 0, StripUntrustedForwardingHeaders
