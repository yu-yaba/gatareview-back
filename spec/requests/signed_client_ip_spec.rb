# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signed client IP forwarding for rate limits', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:secret) { 'test-only-forwarding-secret-0123456789abcdef' }
  # Every server-side call from Vercel arrives from the same egress address.
  let(:vercel_egress) { { 'REMOTE_ADDR' => '10.2.0.1', 'HTTP_X_FORWARDED_FOR' => '198.51.100.200' } }
  let(:rate_limit_client) do
    Rack::MockRequest.new(Rack::Attack.new(->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] }))
  end

  around do |example|
    original_store = Rack::Attack.cache.store
    original_dyno = ENV.fetch('DYNO', nil)
    ENV['DYNO'] = 'web.1'
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.cache.reset!
    travel_to(Time.utc(2026, 11, 9, 3, 10, 10)) { example.run }
  ensure
    Rack::Attack.cache.store = original_store
    ENV['DYNO'] = original_dyno
  end

  before { stub_const('SignedClientIp::SECRET', secret) }

  def signed_headers(ip, method: 'GET', path: '/api/v1/lectures', key: secret, timestamp: Time.now.to_i)
    {
      'HTTP_X_GATAREVIEW_CLIENT_IP' => ip,
      'HTTP_X_GATAREVIEW_CLIENT_IP_TIMESTAMP' => timestamp.to_s,
      'HTTP_X_GATAREVIEW_CLIENT_IP_SIGNATURE' =>
        SignedClientIp.signature(key, timestamp: timestamp.to_s, method: method, path: path, ip: ip)
    }
  end

  def statuses(count, method: :get, path: '/api/v1/lectures')
    Array.new(count) { |index| rate_limit_client.public_send(method, path, yield(index)).status }
  end

  # Runs the request through Rack::Attack (which normalizes PATH_INFO) and
  # returns the throttle key the API would use for it.
  let(:key_echo) do
    Rack::MockRequest.new(
      Rack::Attack.new(->(env) { [200, {}, [RateLimitDiscriminator.throttle_key(Rack::Attack::Request.new(env))]] })
    )
  end

  def key_for(headers, method: 'GET', path: '/api/v1/lectures')
    key_echo.request(method, path, vercel_egress.merge(headers)).body
  end

  it 'matches the signature format shared with the frontend' do
    expect(
      SignedClientIp.signature(secret, timestamp: '1762650000', method: 'GET',
                                       path: '/api/v1/lectures/42/reviews', ip: '203.0.113.7')
    ).to eq('1736d968df87e6b8f10b8fa1f27ce05e6904e7c4576bd7815bca0fab839e2e69')
    expect(
      SignedClientIp.signature(secret, timestamp: '1762650000', method: 'POST',
                                       path: '/api/v1/auth/google', ip: '2001:db8:1:2::abcd')
    ).to eq('279db82b47ef2a930667238f495a20484fb897627828a461c50b0e6d26abcc5a')
  end

  it 'gives each signed visitor behind the Vercel egress address a separate API bucket' do
    limit = Rack::Attack::API_LIMIT_PER_WORKER

    exhausted = statuses(limit + 1) { vercel_egress.merge(signed_headers('203.0.113.7')) }
    other_visitor = statuses(1) { vercel_egress.merge(signed_headers('203.0.113.8')) }
    unsigned_call = statuses(1) { vercel_egress }

    expect(exhausted).to eq(([200] * limit) + [429])
    expect(other_visitor).to eq([200])
    expect(unsigned_call).to eq([200])
  end

  it 'keeps Google sign-ins of different signed visitors apart' do
    limit = Rack::Attack::AUTH_LIMIT_PER_WORKER
    path = '/api/v1/auth/google'

    first = statuses(limit + 1, method: :post, path: path) do
      vercel_egress.merge(signed_headers('203.0.113.7', method: 'POST', path: path))
    end
    second = statuses(1, method: :post, path: path) do
      vercel_egress.merge(signed_headers('203.0.113.8', method: 'POST', path: path))
    end

    expect(first).to eq(([200] * limit) + [429])
    expect(second).to eq([200])
  end

  it 'passes the signed headers through the full Rails middleware stack' do
    allow(HTTParty).to receive(:get).and_return(double(success?: false, code: 400, message: 'Bad Request'))
    limit = Rack::Attack::AUTH_LIMIT_PER_WORKER
    headers = vercel_egress.merge(signed_headers('203.0.113.7', method: 'POST', path: '/api/v1/auth/google'))

    limit.times do
      post '/api/v1/auth/google', params: { token: 'fake-token' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
    post '/api/v1/auth/google', params: { token: 'fake-token' }, headers: headers
    expect(response).to have_http_status(:too_many_requests)

    other = vercel_egress.merge(signed_headers('203.0.113.8', method: 'POST', path: '/api/v1/auth/google'))
    post '/api/v1/auth/google', params: { token: 'fake-token' }, headers: other
    expect(response).to have_http_status(:unauthorized)
  end

  it 'ignores a forged client IP without a valid signature' do
    limit = Rack::Attack::API_LIMIT_PER_WORKER
    forged = statuses(limit + 1) do |index|
      ip = "203.0.113.#{(index % 250) + 1}"
      vercel_egress.merge(
        'HTTP_X_GATAREVIEW_CLIENT_IP' => ip,
        'HTTP_X_GATAREVIEW_CLIENT_IP_TIMESTAMP' => Time.now.to_i.to_s,
        'HTTP_X_GATAREVIEW_CLIENT_IP_SIGNATURE' => index.even? ? '0' * 64 : 'not-a-signature'
      )
    end

    expect(forged).to eq(([200] * limit) + [429])
  end

  it 'falls back to the router-observed address for every invalid header set' do
    router_key = key_for({})
    valid = signed_headers('203.0.113.7')
    invalid_header_sets = {
      'IP only' => valid.slice('HTTP_X_GATAREVIEW_CLIENT_IP'),
      'no signature' => valid.except('HTTP_X_GATAREVIEW_CLIENT_IP_SIGNATURE'),
      'no timestamp' => valid.except('HTTP_X_GATAREVIEW_CLIENT_IP_TIMESTAMP'),
      'wrong secret' => signed_headers('203.0.113.7', key: 'another-secret-that-is-at-least-32-bytes-long'),
      'IP swapped after signing' => valid.merge('HTTP_X_GATAREVIEW_CLIENT_IP' => '203.0.113.99'),
      'timestamp changed after signing' =>
        valid.merge('HTTP_X_GATAREVIEW_CLIENT_IP_TIMESTAMP' => (Time.now.to_i + 1).to_s),
      'signed for another path' => signed_headers('203.0.113.7', path: '/api/v1/reviews/latest'),
      'signed for another method' => signed_headers('203.0.113.7', method: 'POST'),
      'expired' => signed_headers('203.0.113.7', timestamp: Time.now.to_i - 61),
      'too far in the future' => signed_headers('203.0.113.7', timestamp: Time.now.to_i + 11),
      'upper-case signature' => valid.merge(
        'HTTP_X_GATAREVIEW_CLIENT_IP_SIGNATURE' => valid['HTTP_X_GATAREVIEW_CLIENT_IP_SIGNATURE'].upcase
      ),
      'signed non-address' => signed_headers('not-an-ip'),
      'signed CIDR' => signed_headers('203.0.113.0/24'),
      'signed list' => signed_headers('203.0.113.7, 203.0.113.8'),
      'signed zone ID' => signed_headers('fe80::1%eth0')
    }

    invalid_header_sets.each do |label, headers|
      expect(key_for(headers)).to eq(router_key), label
    end
    expect(router_key).to eq('198.51.100.200')
  end

  it 'accepts a signature that is up to 60 seconds old and normalizes the path like Rack::Attack' do
    expect(key_for(signed_headers('203.0.113.7', timestamp: Time.now.to_i - 60))).to eq('203.0.113.7')
    expect(key_for(signed_headers('203.0.113.7', timestamp: Time.now.to_i + 10))).to eq('203.0.113.7')
    expect(
      key_for(signed_headers('203.0.113.7', path: '/api/v1/lectures/42'), path: '/api//v1//lectures//42/')
    ).to eq('203.0.113.7')
  end

  it 'counts a replayed header set against the signed visitor, not as a new bucket' do
    limit = Rack::Attack::API_LIMIT_PER_WORKER
    replayed = signed_headers('203.0.113.7')

    expect(statuses(limit + 1) { vercel_egress.merge(replayed) }).to eq(([200] * limit) + [429])
  end

  it 'ignores signed headers when the backend has no forwarding secret' do
    stub_const('SignedClientIp::SECRET', nil)

    expect(key_for(signed_headers('203.0.113.7'))).to eq('198.51.100.200')
  end

  it 'refuses forwarding secrets shorter than 32 bytes' do
    expect(SignedClientIp.configured_secret('RATE_LIMIT_FORWARDING_SECRET' => 'a' * 31)).to be_nil
    expect(SignedClientIp.configured_secret('RATE_LIMIT_FORWARDING_SECRET' => '')).to be_nil
    expect(SignedClientIp.configured_secret({})).to be_nil
    expect(SignedClientIp.configured_secret('RATE_LIMIT_FORWARDING_SECRET' => 'a' * 32)).to eq('a' * 32)
  end

  it 'counts IPv6 visitors per /64 and IPv4-mapped addresses as IPv4' do
    expect(key_for(signed_headers('2001:db8:1:2::1'))).to eq('2001:db8:1:2::/64')
    expect(key_for(signed_headers('2001:db8:1:2:ffff:ffff:ffff:ffff'))).to eq('2001:db8:1:2::/64')
    expect(key_for(signed_headers('2001:db8:1:3::1'))).to eq('2001:db8:1:3::/64')
    expect(key_for(signed_headers('::ffff:203.0.113.7'))).to eq('203.0.113.7')
  end

  it 'does not let an IPv6 visitor rotate addresses inside one /64 to escape the limit' do
    limit = Rack::Attack::API_LIMIT_PER_WORKER
    rotated = statuses(limit + 1) { |index| vercel_egress.merge(signed_headers("2001:db8:1:2::#{index.to_s(16)}")) }

    expect(rotated).to eq(([200] * limit) + [429])
  end

  it 'logs the throttled rule and key source without the address' do
    allow(Rails.logger).to receive(:warn)
    limit = Rack::Attack::API_LIMIT_PER_WORKER
    statuses(limit + 1) { vercel_egress.merge(signed_headers('203.0.113.7')) }
    statuses(limit + 1) { { 'REMOTE_ADDR' => '10.2.0.9', 'HTTP_X_FORWARDED_FOR' => '198.51.100.201' } }

    expect(Rails.logger).to have_received(:warn).with('[rack-attack] throttled rule=api/ip key_source=signed').once
    expect(Rails.logger).to have_received(:warn).with('[rack-attack] throttled rule=api/ip key_source=router').once
    expect(Rails.logger).not_to have_received(:warn).with(/203\.0\.113\.7|198\.51\.100\.201/)
  end

  it 'uses the signed address for the reCAPTCHA remote IP' do
    env = Rack::MockRequest.env_for('/api/v1/lectures', vercel_egress.merge(signed_headers('203.0.113.7')))

    expect(RateLimitDiscriminator.client_ip(ActionDispatch::Request.new(env))).to eq('203.0.113.7')
  end
end
