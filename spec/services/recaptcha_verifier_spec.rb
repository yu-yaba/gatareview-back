# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RecaptchaVerifier do
  around do |example|
    previous_secret = ENV.fetch('RECAPTCHA_SECRET_KEY', nil)
    ENV['RECAPTCHA_SECRET_KEY'] = 'test-secret'
    example.run
  ensure
    ENV['RECAPTCHA_SECRET_KEY'] = previous_secret
  end

  def stub_google_response(hostname:)
    body = {
      success: true,
      action: 'submit',
      score: 0.9,
      hostname: hostname
    }.to_json

    allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, body: body))
  end

  it 'accepts a token issued for an allowed hostname' do
    stub_google_response(hostname: 'www.gatareview.com')
    verifier = described_class.new(
      'token',
      'submit',
      0.5,
      remote_ip: '203.0.113.10',
      allowed_hostnames: ['www.gatareview.com']
    )

    expect(verifier.verify).to be(true)
    expect(verifier.hostname).to eq('www.gatareview.com')
    expect(HTTParty).to have_received(:post).with(
      'https://www.google.com/recaptcha/api/siteverify',
      body: hash_including(remoteip: '203.0.113.10')
    )
  end

  it 'rejects a token issued for another hostname' do
    stub_google_response(hostname: 'attacker.example')
    verifier = described_class.new('token', 'submit', 0.5, allowed_hostnames: ['www.gatareview.com'])

    expect(verifier.verify).to be(false)
  end
end
