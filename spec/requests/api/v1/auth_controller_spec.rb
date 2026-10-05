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
  end
end
