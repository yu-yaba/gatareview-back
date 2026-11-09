# frozen_string_literal: true

require 'ipaddr'
require 'openssl'
require_relative '../web_concurrency'

# The Next.js server calls this API on behalf of browsers (lecture pages,
# searches, Google sign-in). Seen from Heroku, all of those calls come from
# Vercel's egress addresses, so per-IP limits would make every visitor share one
# bucket. For those calls the frontend sends the visitor address observed by
# Vercel's edge, signed with RATE_LIMIT_FORWARDING_SECRET (shared only by the two
# servers). The address is used only when the signature is valid and fresh;
# anything else falls back to the router-observed address.
#
# Signed message (UTF-8, joined with "\n"):
#   v1, unix timestamp in seconds, HTTP method, request path, client IP
# The path excludes the query and is normalized the way Rack::Attack rewrites
# PATH_INFO before throttles run (collapsed slashes, no trailing slash,
# upper-case percent escapes). Signature: lowercase hex HMAC-SHA256. Keep in sync
# with the frontend's app/_helpers/clientIpSignature.ts.
module SignedClientIp
  module_function

  SECRET_ENV = 'RATE_LIMIT_FORWARDING_SECRET'
  IP_HEADER = 'HTTP_X_GATAREVIEW_CLIENT_IP'
  TIMESTAMP_HEADER = 'HTTP_X_GATAREVIEW_CLIENT_IP_TIMESTAMP'
  SIGNATURE_HEADER = 'HTTP_X_GATAREVIEW_CLIENT_IP_SIGNATURE'
  VERSION = 'v1'
  MIN_SECRET_BYTES = 32
  # A signature is only valid for a short time so that a leaked header set
  # cannot be replayed for long.
  MAX_AGE_SECONDS = 60
  MAX_CLOCK_SKEW_SECONDS = 10
  TIMESTAMP_FORMAT = /\A\d{1,11}\z/
  SIGNATURE_FORMAT = /\A[0-9a-f]{64}\z/
  MAX_IP_LENGTH = 45

  def configured_secret(env = ENV)
    secret = env[SECRET_ENV].to_s
    secret if secret.bytesize >= MIN_SECRET_BYTES
  end

  def signature(secret, timestamp:, method:, path:, ip:)
    OpenSSL::HMAC.hexdigest('SHA256', secret, [VERSION, timestamp, method, path, ip].join("\n"))
  end

  # Returns the normalized forwarded address, or nil unless the request carries
  # a valid signature that is no older than MAX_AGE_SECONDS.
  def verified_ip(request, secret: SECRET, now: Time.now.to_i)
    return if secret.nil?

    ip = request.get_header(IP_HEADER)
    timestamp = request.get_header(TIMESTAMP_HEADER)
    provided = request.get_header(SIGNATURE_HEADER)
    return unless well_formed?(ip, timestamp, provided)
    return unless (now - MAX_AGE_SECONDS..now + MAX_CLOCK_SKEW_SECONDS).cover?(timestamp.to_i)

    expected = signature(secret, timestamp: timestamp, method: request.request_method, path: request.path, ip: ip)
    return unless ActiveSupport::SecurityUtils.secure_compare(expected, provided)

    RateLimitDiscriminator.normalized_ip(ip)
  end

  def well_formed?(ip, timestamp, provided)
    ip.is_a?(String) && ip.bytesize <= MAX_IP_LENGTH &&
      timestamp.is_a?(String) && timestamp.match?(TIMESTAMP_FORMAT) &&
      provided.is_a?(String) && provided.match?(SIGNATURE_FORMAT)
  end

  SECRET = configured_secret
end

if ENV[SignedClientIp::SECRET_ENV].present? && SignedClientIp::SECRET.nil?
  Rails.logger.warn(
    "#{SignedClientIp::SECRET_ENV} is shorter than #{SignedClientIp::MIN_SECRET_BYTES} bytes; " \
    'ignoring forwarded client IPs'
  )
end

module RateLimitDiscriminator
  module_function

  IPV6_BUCKET_PREFIX = 64

  # The address used for rate limiting and reCAPTCHA: a validly signed address
  # forwarded by the frontend server, otherwise the router-observed address.
  def client_ip(request, heroku: ENV['DYNO'].present?)
    SignedClientIp.verified_ip(request) || observed_ip(request, heroku: heroku)
  end

  # Heroku appends the router-observed address to X-Forwarded-For. Other
  # deployments use the socket address until their proxy contract is configured.
  # Rack's `ip` and Rails' `remote_ip` prefer unverified Forwarded headers.
  def observed_ip(request, heroku:)
    socket_address = normalized_ip(request.get_header('REMOTE_ADDR'))
    return socket_address || 'unknown' unless heroku

    observed_address = request.get_header('HTTP_X_FORWARDED_FOR').to_s.split(',', -1).last.to_s.strip
    normalized_ip(observed_address) || socket_address || 'unknown'
  end

  # Throttle key. An IPv6 subscriber usually controls a whole /64, so addresses
  # inside one /64 share a bucket instead of each getting a fresh limit.
  def throttle_key(request)
    bucket(client_ip(request))
  end

  def bucket(ip)
    address = IPAddr.new(ip)
    address.ipv6? ? "#{address.mask(IPV6_BUCKET_PREFIX)}/#{IPV6_BUCKET_PREFIX}" : address.to_s
  rescue IPAddr::Error
    ip
  end

  def normalized_ip(value)
    return if value.blank? || value.include?('/') || value.include?('%')

    IPAddr.new(value).native.to_s
  rescue IPAddr::Error
    nil
  end
end

# Counters live in an in-process MemoryStore: its increment is atomic across
# Puma threads, unlike Rails' default FileStore, which let about twice the limit
# through under bursts. Puma forks the preloaded app, so each worker process
# counts on its own; every limit is therefore divided by the worker count to keep
# the per-dyno total close to the configured value. With several web dynos each
# dyno counts separately as well.
module RateLimitSettings
  module_function

  STORE_SIZE = 32.megabytes

  def cache_store(env = Rails.env)
    # Request specs that exercise the limits install their own MemoryStore.
    return ActiveSupport::Cache::NullStore.new if env.test?

    ActiveSupport::Cache::MemoryStore.new(size: STORE_SIZE)
  end

  def per_worker(limit, workers: WebConcurrency.workers)
    [(limit.to_f / [workers, 1].max).ceil, 1].max
  end
end

module Rack
  class Attack
    # Per-dyno limits as configured. Each worker enforces its share below.
    AUTH_LIMIT = Integer(ENV.fetch('AUTH_RATE_LIMIT_PER_MINUTE', 10))
    API_LIMIT = Integer(ENV.fetch('API_RATE_LIMIT_PER_FIVE_MINUTES', 300))
    AUTH_LIMIT_PER_WORKER = RateLimitSettings.per_worker(AUTH_LIMIT)
    API_LIMIT_PER_WORKER = RateLimitSettings.per_worker(API_LIMIT)
    GOOGLE_AUTH_PATH_PATTERN = %r{\A/api/v1/auth/google(?:\.[^/]+)?/?\z}

    cache.store = RateLimitSettings.cache_store

    throttle('auth/google/ip', limit: AUTH_LIMIT_PER_WORKER, period: 1.minute) do |request|
      RateLimitDiscriminator.throttle_key(request) if request.post? && request.path.match?(GOOGLE_AUTH_PATH_PATTERN)
    end

    throttle('api/ip', limit: API_LIMIT_PER_WORKER, period: 5.minutes) do |request|
      RateLimitDiscriminator.throttle_key(request) if request.path.start_with?('/api/')
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

# Log which rule fired and whether the key came from a signed forwarded address,
# without the address itself.
ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  source = SignedClientIp.verified_ip(request) ? 'signed' : 'router'
  Rails.logger.warn("[rack-attack] throttled rule=#{request.env['rack.attack.matched']} key_source=#{source}")
end
