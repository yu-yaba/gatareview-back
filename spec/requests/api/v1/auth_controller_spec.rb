# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Auth', type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('JWT_SECRET_KEY').and_return('test-only-jwt-secret-with-at-least-32-bytes')
  end

  let(:user) { FactoryBot.create(:user) }
  let(:token) { JsonWebToken.encode(user.jwt_payload, 1.hour.from_now) }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  describe 'POST /api/v1/auth/google' do
    let(:google_info) do
      {
        'aud' => 'test-google-client-id', 'sub' => 'test-google-subject',
        'email' => 'oauth-test@example.com', 'name' => 'OAuth Test',
        'email_verified' => true, 'iss' => 'https://accounts.google.com',
        'exp' => 1.hour.from_now.to_i.to_s
      }
    end

    before do
      allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return('test-google-client-id')
      allow(HTTParty).to receive(:get).with(
        'https://oauth2.googleapis.com/tokeninfo', query: { id_token: 'test-google-id-token' }, timeout: 10
      ).and_return(instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: google_info))
    end

    [false, true].each do |remember|
      it "issues a usable #{remember ? 30 : 7}-day token for a verified Google identity" do
        post '/api/v1/auth/google', params: { token: 'test-google-id-token', remember: remember }, as: :json
        expect(response).to have_http_status(:ok)
        issued_token = response.parsed_body.fetch('token')
        claims = JsonWebToken.decode(issued_token)
        expect(claims[:token_version]).to eq(0)
        expect(claims[:exp] - Time.current.to_i).to be_within(5).of((remember ? 30 : 7).days.to_i)

        get '/api/v1/auth/me', headers: { 'Authorization' => "Bearer #{issued_token}" }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('user', 'email')).to eq('oauth-test@example.com')
      end
    end

    {
      'one byte below the limit' => 'a' * ((16 * 1024) - 1),
      'exactly the byte limit' => 'a' * (16 * 1024),
      'multibyte text exactly at the byte limit' => "#{'あ' * 5461}a"
    }.each do |description, input|
      it "verifies Google token input with #{description}" do
        allow(HTTParty).to receive(:get).with(
          'https://oauth2.googleapis.com/tokeninfo', query: { id_token: input }, timeout: 10
        ).and_return(instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: google_info))

        expect do
          post '/api/v1/auth/google', params: { token: input }, as: :json
        end.to change(User, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(HTTParty).to have_received(:get).with(
          'https://oauth2.googleapis.com/tokeninfo', query: { id_token: input }, timeout: 10
        ).once
        expect(JsonWebToken.decode(response.parsed_body.fetch('token'))[:user_id]).to eq(User.last.id)
      end
    end

    {
      'ASCII text one byte over the limit' => 'a' * ((16 * 1024) + 1),
      'multibyte text one byte over the limit' => "#{'あ' * 5461}ab"
    }.each do |description, input|
      it "rejects #{description} without provider work or account changes" do
        existing_user = create(:user, provider_id: google_info.fetch('sub'))
        original_account = existing_user.attributes
        expect(HTTParty).not_to receive(:get)

        expect do
          post '/api/v1/auth/google', params: { token: input }, as: :json
        end.not_to change(User, :count)

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body).not_to have_key('token')
        expect(existing_user.reload.attributes).to eq(original_account)
      end
    end

    {
      'aud' => 'another-client', 'iss' => 'https://invalid.example',
      'email_verified' => false, 'exp' => '0', 'sub' => ''
    }.each do |field, invalid_value|
      it "rejects an identity with invalid #{field} without creating a user" do
        google_info[field] = invalid_value
        expect do
          post '/api/v1/auth/google', params: { token: 'test-google-id-token' }, as: :json
        end.not_to change(User, :count)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'updates the verified email and removes privileges tied to the old email' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ADMIN_EMAILS', '').and_return('retired-admin@example.test')
      allow(ENV).to receive(:fetch).with('ADMIN_EMAIL', nil).and_return(nil)
      existing_user = create(:user, email: 'retired-admin@example.test', provider_id: google_info.fetch('sub'))
      old_headers = { 'Authorization' => "Bearer #{JsonWebToken.encode(existing_user.jwt_payload)}" }

      post '/api/v1/auth/google', params: { token: 'test-google-id-token' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('user')).to include(
        'id' => existing_user.id, 'email' => google_info.fetch('email'), 'admin' => false
      )
      expect(existing_user.reload.email).to eq(google_info.fetch('email'))

      get '/api/v1/admin/review-access', headers: old_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'fails closed on an email collision without merging or changing either account' do
      existing_user = create(:user, email: 'old-email@example.test', provider_id: google_info.fetch('sub'))
      other_user = create(:user, email: google_info.fetch('email'), provider_id: 'another-google-subject')
      original_accounts = [existing_user.attributes, other_user.attributes]

      expect do
        post '/api/v1/auth/google', params: { token: 'test-google-id-token' }, as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body).not_to have_key('token')
      expect([existing_user.reload.attributes, other_user.reload.attributes]).to eq(original_accounts)
    end
  end

  describe 'POST /api/v1/auth/logout' do
    it 'invalidates JWTs issued before logout' do
      post '/api/v1/auth/logout', headers: headers

      expect(response).to have_http_status(:ok)
      expect(user.reload.token_version).to eq(1)

      get '/api/v1/auth/me', headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps another user signed in and accepts a newly issued token' do
      other_user = create(:user)
      other_headers = { 'Authorization' => "Bearer #{JsonWebToken.encode(other_user.jwt_payload)}" }
      post '/api/v1/auth/logout', headers: headers

      get '/api/v1/auth/me', headers: other_headers
      expect(response).to have_http_status(:ok)
      expect(other_user.reload.token_version).to eq(0)

      fresh_headers = { 'Authorization' => "Bearer #{JsonWebToken.encode(user.reload.jwt_payload)}" }
      get '/api/v1/auth/me', headers: fresh_headers
      expect(response).to have_http_status(:ok)
    end

    it 'rejects unauthenticated logout without changing token versions' do
      post '/api/v1/auth/logout'

      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.token_version).to eq(0)
    end
  end

  describe 'GET /api/v1/auth/me' do
    it 'rejects legacy JWTs without a token version' do
      legacy_token = JsonWebToken.encode({ user_id: user.id }, 1.hour.from_now)

      get '/api/v1/auth/me', headers: { 'Authorization' => "Bearer #{legacy_token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    ['', 'Basic local-test', 'Bearer', 'Bearer invalid token'].each do |authorization|
      it 'rejects a missing or invalid authentication header without personal data' do
        get '/api/v1/auth/me', headers: { 'Authorization' => authorization }

        expect(response).to have_http_status(:unauthorized)
        expect(response.body.include?(user.email)).to be(false)
      end
    end

    {
      'missing user ID' => ->(claims) { claims.delete(:user_id) },
      'array user ID' => ->(claims) { claims[:user_id] = [claims[:user_id]] },
      'object user ID' => ->(claims) { claims[:user_id] = { id: claims[:user_id] } },
      'floating point user ID' => ->(claims) { claims[:user_id] = claims[:user_id].to_f },
      'user ID with trailing text' => ->(claims) { claims[:user_id] = "#{claims[:user_id]}suffix" },
      'missing token version' => ->(claims) { claims.delete(:token_version) },
      'string token version' => ->(claims) { claims[:token_version] = claims[:token_version].to_s },
      'fractional token version' => ->(claims) { claims[:token_version] = 0.5 },
      'missing expiry' => ->(claims) { claims.delete(:exp) },
      'floating point expiry' => ->(claims) { claims[:exp] = claims[:exp].to_f },
      'missing issued-at time' => ->(claims) { claims.delete(:iat) },
      'future issued-at time' => ->(claims) { claims[:iat] = 1.hour.from_now.to_i }
    }.each do |description, change|
      it "rejects signed test fixtures with #{description}" do
        claims = user.jwt_payload.merge(exp: 1.hour.from_now.to_i, iat: Time.current.to_i)
        change.call(claims)
        local_token = JWT.encode(claims, JsonWebToken.secret_key, 'HS256')

        get '/api/v1/auth/me', headers: { 'Authorization' => "Bearer #{local_token}" }

        expect(response).to have_http_status(:unauthorized)
        expect(response.body.include?(user.email)).to be(false)
      end
    end

    %i[exp iat].each do |field|
      it "does not issue test fixtures with non-numeric #{field}" do
        claims = user.jwt_payload.merge(exp: 1.hour.from_now.to_i, iat: Time.current.to_i)
        claims[field] = claims[field].to_s

        expect { JWT.encode(claims, JsonWebToken.secret_key, 'HS256') }.to raise_error(JWT::InvalidPayload)
      end
    end

    it 'accepts the normal integer payload with a small issued-at clock difference' do
      claims = user.jwt_payload.merge(exp: 1.hour.from_now.to_i, iat: 15.seconds.from_now.to_i)
      local_token = JWT.encode(claims, JsonWebToken.secret_key, 'HS256')

      get '/api/v1/auth/me', headers: { 'Authorization' => "Bearer #{local_token}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('user', 'id')).to eq(user.id)
    end
  end

  describe 'invalid Google authentication input' do
    [nil, '', ' ', [], { invalid: 'value' }, 123, true].each do |input|
      it 'rejects empty or non-string input before external verification' do
        calls = 0
        failure = google_failure_response('Local test only')
        allow(HTTParty).to receive(:get) do
          calls += 1
          failure
        end

        expect do
          post '/api/v1/auth/google', params: { token: input }, as: :json
        end.not_to change(User, :count)

        expect(response).to have_http_status(:unauthorized)
        expect(calls).to eq(0)
      end
    end
  end

  describe 'authentication log privacy' do
    let(:private_marker) { SecureRandom.hex(24) }
    let(:private_email) { 'fixture-private@example.test' }
    let(:messages) { [] }

    before do
      %i[info warn error].each do |level|
        allow(Rails.logger).to receive(level) { |message| messages << message.to_s }
      end
    end

    it 'does not log token-bearing messages or backtraces from HTTP exceptions' do
      failure = HTTParty::Error.new("Local URI id_token=#{private_marker} email=#{private_email}")
      failure.set_backtrace(["local-test/#{private_marker}:1"])
      allow(HTTParty).to receive(:get).and_raise(failure)

      post '/api/v1/auth/google', params: { token: 'local-google-test-input' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(messages.join.include?(private_marker)).to be(false)
      expect(messages.join.include?(private_email)).to be(false)
    end

    it 'does not log provider error messages containing private values' do
      failure = google_failure_response("Local provider error #{private_marker} #{private_email}")
      allow(HTTParty).to receive(:get).and_return(failure)

      post '/api/v1/auth/google', params: { token: 'local-google-test-input' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(messages.join.include?(private_marker)).to be(false)
      expect(messages.join.include?(private_email)).to be(false)
    end

    it 'does not log raw duplicate-account database exception messages' do
      failure = ActiveRecord::RecordNotUnique.new("Local duplicate email #{private_email} #{private_marker}")
      allow(User).to receive(:create!).and_raise(failure)
      fixture_identity = { 'sub' => 'local-log-privacy-user', 'email' => private_email, 'name' => 'Local fixture' }

      expect { User.from_google_oauth(fixture_identity) }.to raise_error(ActiveRecord::RecordNotFound)

      expect(messages.join.include?(private_marker)).to be(false)
      expect(messages.join.include?(private_email)).to be(false)
    end
  end

  def google_failure_response(message)
    request = instance_double(HTTParty::Request, options: {})
    http_response = Net::HTTPUnauthorized.new('1.1', '401', message)
    HTTParty::Response.new(request, http_response, -> { {} }, body: '{}')
  end
end
