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

  it 'RemoteIpより前に組み込まれていること' do
    middlewares = Rails.application.middleware.map(&:klass)

    expect(middlewares.index(described_class)).to be < middlewares.index(ActionDispatch::RemoteIp)
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
