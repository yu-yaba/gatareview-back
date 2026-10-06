# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JsonWebToken do
  describe '.secret_key' do
    [nil, '', ' ', 'x' * 31].each do |secret|
      it 'rejects missing or short dedicated keys in production' do
        expect do
          described_class.secret_key(environment: 'production', configured_secret: secret)
        end.to raise_error(JsonWebToken::ConfigurationError)
      end
    end

    it 'accepts a dedicated key of at least 32 bytes' do
      secret = SecureRandom.hex(32)
      expect(described_class.secret_key(environment: 'production', configured_secret: secret)).to eq(secret)
    end

    it 'derives stable, separate keys only for development and test' do
      test_key = described_class.secret_key(environment: 'test', configured_secret: nil)
      expect(test_key.bytesize).to be >= 32
      expect(described_class.secret_key(environment: 'test', configured_secret: nil)).to eq(test_key)
      expect(described_class.secret_key(environment: 'development', configured_secret: nil)).not_to eq(test_key)
    end

    it 'rejects a configured short key even in test' do
      expect do
        described_class.secret_key(environment: 'test', configured_secret: 'weak')
      end.to raise_error(JsonWebToken::ConfigurationError)
    end
  end

  describe '.decode' do
    let(:payload) { { user_id: 123, token_version: 0, exp: 1.hour.from_now.to_i } }

    it 'round trips a valid signed token' do
      expect(described_class.decode(described_class.encode(payload))[:user_id]).to eq(123)
    end

    [123, true, ['invalid-input'], { invalid: 'input' }].each do |input|
      it 'rejects non-string input without raising an exception' do
        expect(described_class.decode(input)).to be_nil
      end
    end

    it 'does not include exception contents in token rejection logs' do
      marker = SecureRandom.hex(24)
      messages = []
      allow(Rails.logger).to receive(:error) { |message| messages << message.to_s }
      allow(JWT).to receive(:decode).and_raise(JWT::DecodeError.new("Local private value #{marker}"))

      expect(described_class.decode('local-invalid-input')).to be_nil
      expect(messages.join.include?(marker)).to be(false)
    end

    it 'rejects expired tokens' do
      expect(described_class.decode(described_class.encode(payload, 1.hour.ago))).to be_nil
    end

    it 'rejects forged and unsigned tokens' do
      expect(described_class.decode(JWT.encode(payload, SecureRandom.hex(32), 'HS256'))).to be_nil
      expect(described_class.decode(JWT.encode(payload, nil, 'none'))).to be_nil
    end

    it 'rejects a different signing algorithm' do
      expect(described_class.decode(JWT.encode(payload, described_class.secret_key, 'HS384'))).to be_nil
    end
  end
end
