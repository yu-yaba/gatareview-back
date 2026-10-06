# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API rate limiting', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:rate_limit_client) do
    Rack::MockRequest.new(Rack::Attack.new(->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] }))
  end

  around do |example|
    original_store = Rack::Attack.cache.store
    original_dyno = ENV.fetch('DYNO', nil)
    ENV.delete('DYNO')
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.cache.reset!
    travel_to(Time.utc(2026, 10, 6, 3, 10, 10)) { example.run }
  ensure
    Rack::Attack.cache.store = original_store
    ENV['DYNO'] = original_dyno
  end

  it 'throttles repeated Google authentication requests by IP' do
    google_response = double(success?: false, code: 400, message: 'Bad Request')
    allow(HTTParty).to receive(:get).and_return(google_response)

    Rack::Attack::AUTH_LIMIT.times do
      post '/api/v1/auth/google', params: { token: 'invalid-token' }
      expect(response).to have_http_status(:unauthorized)
    end

    post '/api/v1/auth/google', params: { token: 'invalid-token' }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After']).to be_present
    expect(HTTParty).to have_received(:get).exactly(Rack::Attack::AUTH_LIMIT).times
  end

  it 'ignores changing Forwarded headers and client-supplied X-Forwarded-For prefixes on Heroku' do
    ENV['DYNO'] = 'web.1'

    statuses = (Rack::Attack::AUTH_LIMIT + 1).times.map do |index|
      rate_limit_client.post(
        '/api/v1/auth/google',
        'REMOTE_ADDR' => '10.2.0.1',
        'HTTP_X_FORWARDED_FOR' => "203.0.113.#{index + 1}, 198.51.100.9",
        'HTTP_FORWARDED' => "for=192.0.2.#{index + 1}",
        'HTTP_CLIENT_IP' => "192.0.2.#{index + 1}"
      ).status
    end

    expect(statuses).to eq(([200] * Rack::Attack::AUTH_LIMIT) + [429])
  end

  it 'keeps the API-wide limit effective when untrusted forwarding headers change' do
    ENV['DYNO'] = 'web.1'

    statuses = (Rack::Attack::API_LIMIT + 1).times.map do |index|
      rate_limit_client.get(
        '/api/v1/lectures',
        'REMOTE_ADDR' => '10.2.0.1',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.10, 198.51.100.9',
        'HTTP_FORWARDED' => "for=192.0.2.#{(index % 250) + 1}"
      ).status
    end

    expect(statuses).to eq(([200] * Rack::Attack::API_LIMIT) + [429])
  end

  it 'keeps different router-observed clients in separate buckets' do
    ENV['DYNO'] = 'web.1'
    headers = { 'REMOTE_ADDR' => '10.2.0.1', 'HTTP_X_FORWARDED_FOR' => '198.51.100.9' }

    Rack::Attack::AUTH_LIMIT.times do
      expect(rate_limit_client.post('/api/v1/auth/google', headers).status).to eq(200)
    end

    expect(rate_limit_client.post('/api/v1/auth/google', headers).status).to eq(429)
    headers['HTTP_X_FORWARDED_FOR'] = '198.51.100.10'
    expect(rate_limit_client.post('/api/v1/auth/google', headers).status).to eq(200)
  end

  it 'uses the socket address outside Heroku even when all forwarding headers change' do
    statuses = (Rack::Attack::AUTH_LIMIT + 1).times.map do |index|
      rate_limit_client.post(
        '/api/v1/auth/google',
        'REMOTE_ADDR' => '192.0.2.20',
        'HTTP_X_FORWARDED_FOR' => "198.51.100.#{index + 1}",
        'HTTP_FORWARDED' => "for=203.0.113.#{index + 1}"
      ).status
    end

    expect(statuses).to eq(([200] * Rack::Attack::AUTH_LIMIT) + [429])
  end

  it 'counts JSON and trailing-slash variants of the Google auth route in the same bucket' do
    Rack::Attack::AUTH_LIMIT.times do |index|
      path = index.even? ? '/api/v1/auth/google.json' : '/api/v1/auth/google/'
      expect(rate_limit_client.post(path, 'REMOTE_ADDR' => '192.0.2.30').status).to eq(200)
    end

    expect(rate_limit_client.post('/api/v1/auth/google', 'REMOTE_ADDR' => '192.0.2.30').status).to eq(429)
  end

  it 'falls back to the socket address for an invalid router-appended address' do
    ['not-an-ip', '198.51.100.0/24', ''].each do |suffix|
      request = Rack::Attack::Request.new(
        Rack::MockRequest.env_for(
          '/',
          'REMOTE_ADDR' => '10.2.0.5',
          'HTTP_X_FORWARDED_FOR' => "198.51.100.9, #{suffix}",
          'HTTP_FORWARDED' => 'for=203.0.113.42'
        )
      )

      expect(RateLimitDiscriminator.client_ip(request, heroku: true)).to eq('10.2.0.5')
    end
  end

  it 'normalizes IPv6 addresses before choosing the rate-limit bucket' do
    request = Rack::Attack::Request.new(
      Rack::MockRequest.env_for('/', 'HTTP_X_FORWARDED_FOR' => '2001:0db8:0:0:0:0:0:1')
    )

    expect(RateLimitDiscriminator.client_ip(request, heroku: true)).to eq('2001:db8::1')
  end

  it 'throttles a real Google route despite repeated slashes, changing query, form and JSON bodies' do
    allow(HTTParty).to receive(:get).and_return(double(success?: false, code: 400, message: 'Bad Request'))

    Rack::Attack::AUTH_LIMIT.times do |index|
      post "//api//v1//auth//google?attempt=#{index}",
           params: { token: 'fake-token' },
           headers: { 'REMOTE_ADDR' => '192.0.2.88', 'HTTP_X_FORWARDED_FOR' => "198.51.100.#{index + 1}" },
           as: index.even? ? :json : nil
      expect(response).to have_http_status(:unauthorized)
    end

    post '//api//v1//auth//google', params: { token: 'fake-token' }, headers: { 'REMOTE_ADDR' => '192.0.2.88' }

    expect(response).to have_http_status(:too_many_requests)
    expect(HTTParty).to have_received(:get).exactly(Rack::Attack::AUTH_LIMIT).times
  end

  it 'keeps anonymous review writes behind the API limit for repeated-slash routes' do
    ip = '192.0.2.89'
    lecture = create(:lecture)
    (Rack::Attack::API_LIMIT - 3).times { rate_limit_client.get('/api/v1/lectures', 'REMOTE_ADDR' => ip) }
    params = { review: { rating: 4.5, content: '匿名投稿の正常なレビュー本文です。' * 3 } }

    3.times do |index|
      post "//api//v1//lectures//#{lecture.id}//reviews?attempt=#{index}",
           params: params,
           headers: { 'REMOTE_ADDR' => ip }, as: :json
      expect(response).to have_http_status(:created)
    end

    post "//api//v1//lectures//#{lecture.id}//reviews", params: params, headers: { 'REMOTE_ADDR' => ip }, as: :json

    expect(response).to have_http_status(:too_many_requests)
    expect(lecture.reviews.count).to eq(3)
  end

  it 'does not apply the API limit to a nearby non-API prefix' do
    (Rack::Attack::API_LIMIT + 1).times do
      expect(rate_limit_client.get('/apiary', 'REMOTE_ADDR' => '192.0.2.90').status).to eq(200)
    end
  end

  it 'does not let a body method-override field bypass POST authentication throttling' do
    allow(HTTParty).to receive(:get).and_return(double(success?: false, code: 400, message: 'Bad Request'))

    Rack::Attack::AUTH_LIMIT.times do
      post '/api/v1/auth/google', params: { token: 'fake-token', _method: 'get' }
      expect(response).to have_http_status(:unauthorized)
    end

    post '/api/v1/auth/google', params: { token: 'fake-token', _method: 'patch' }

    expect(response).to have_http_status(:too_many_requests)
    expect(HTTParty).to have_received(:get).exactly(Rack::Attack::AUTH_LIMIT).times
  end

  it 'does not authenticate through GET or HEAD requests to the POST-only route' do
    expect(HTTParty).not_to receive(:get)

    %i[get head].each do |method|
      send(method, '/api/v1/auth/google', params: { token: 'fake-token', _method: 'post' })
      expect(response.status).to be < 500
    end
  end
end
