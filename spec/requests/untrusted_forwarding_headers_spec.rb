# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StripUntrustedForwardingHeaders, type: :request do
  let(:spoofed_headers) do
    {
      'REMOTE_ADDR' => '10.0.0.5',
      'HTTP_X_FORWARDED_FOR' => '203.0.113.41, 198.51.100.10',
      'HTTP_FORWARDED' => 'for=203.0.113.99;proto=http;host=evil.example',
      'HTTP_CLIENT_IP' => '203.0.113.99'
    }
  end

  it 'ミドルウェアの先頭に組み込まれていること' do
    expect(Rails.application.middleware.first.klass).to eq(described_class)
  end

  it 'force_sslがForwardedのproto=httpを見て301を返さないこと' do
    ssl = ActionDispatch::SSL.new(->(_env) { [200, {}, ['ok']] })
    # Heroku forwards to the dyno over http and vouches for https via X-Forwarded-Proto.
    heroku_env = lambda do
      Rack::MockRequest.env_for(
        'http://gatareview-back.example/api/v1/reviews/total',
        'HTTP_X_FORWARDED_PROTO' => 'https',
        'HTTP_FORWARDED' => 'proto=http'
      )
    end

    expect(ssl.call(heroku_env.call).first).to eq(301)
    expect(described_class.new(ssl).call(heroku_env.call).first).to eq(200)
  end

  it 'ForwardedとClient-Ipだけを取り除き、X-Forwarded-Forは残すこと' do
    received_env = nil
    middleware = described_class.new(lambda do |env|
      received_env = env
      [200, {}, ['ok']]
    end)

    middleware.call(spoofed_headers.dup)

    expect(received_env).not_to include('HTTP_FORWARDED', 'HTTP_CLIENT_IP')
    expect(received_env['HTTP_X_FORWARDED_FOR']).to eq('203.0.113.41, 198.51.100.10')
  end

  it '食い違うForwardedとX-Forwarded-Forがあっても授業一覧が正常に返ること' do
    FactoryBot.create(:lecture)

    get '/api/v1/lectures', headers: spoofed_headers

    expect(response).to have_http_status(:ok)
    expect(request.remote_ip).to eq('198.51.100.10')
  end
end
