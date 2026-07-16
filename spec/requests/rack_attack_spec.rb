# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API rate limiting', type: :request do
  around do |example|
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.cache.reset!
    example.run
  ensure
    Rack::Attack.cache.store = original_store
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
end
