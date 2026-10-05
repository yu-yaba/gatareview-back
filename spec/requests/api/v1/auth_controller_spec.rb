# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Auth', type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('JWT_SECRET_KEY').and_return('test-jwt-secret-key')
  end

  let(:user) { FactoryBot.create(:user) }
  let(:token) { JsonWebToken.encode(user.jwt_payload, 1.hour.from_now) }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  describe 'POST /api/v1/auth/logout' do
    it 'invalidates JWTs issued before logout' do
      post '/api/v1/auth/logout', headers: headers

      expect(response).to have_http_status(:ok)
      expect(user.reload.token_version).to eq(1)

      get '/api/v1/auth/me', headers: headers

      expect(response).to have_http_status(:unauthorized)
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
