# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RecaptchaVerifier, 'adversarial boundaries' do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('RECAPTCHA_SECRET_KEY').and_return('fake-adversarial-secret')
  end

  let(:valid_response) { { 'success' => true, 'action' => 'submit', 'score' => 0.9, 'hostname' => 'gatareview.com' } }

  [nil, [], { fake: 'token' }, 123, 'x' * 65_536].each_with_index do |token, index|
    it "rejects malformed or overlong token case #{index + 1} before external verification" do
      expect(HTTParty).not_to receive(:post)

      expect(described_class.new(token).verify).to be(false)
    end
  end

  [false, 'false', 'true', 1].each do |success|
    it "requires a boolean true success value instead of #{success.inspect}" do
      response = valid_response.merge('success' => success).to_json
      allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, body: response))

      expect(described_class.new('fake-token').verify).to be(false)
    end
  end

  ['0.9', 'NaN', nil, [], {}, -0.1, 1.1].each do |score|
    it "rejects a nonnumeric or out-of-range score #{score.inspect}" do
      response = valid_response.merge('score' => score).to_json
      allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, body: response))

      expect(described_class.new('fake-token').verify).to be(false)
    end
  end

  ['null', '[]', '"string"', '{', '{"success":true,"action":"submit","hostname":"gatareview.com","score":1e309}'].each do |body|
    it "fails closed for unexpected response #{body.inspect}" do
      allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, body: body))

      expect(described_class.new('fake-token').verify).to be(false)
    end
  end

  it 'does not log secret material included in a network exception message' do
    allow(HTTParty).to receive(:post).and_raise(StandardError, 'fake-adversarial-secret fake-token exception')
    expect(Rails.logger).to receive(:error).with('reCAPTCHA verification failed: StandardError')

    expect(described_class.new('fake-token').verify).to be(false)
  end
end
