# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe DatabaseTlsConfiguration do
  it 'uses the system CA default when MYSQL_SSL_CA is absent or empty' do
    [nil, ''].each do |ca_path|
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('MYSQL_SSL_CA').and_return(ca_path)
      yaml = ERB.new(Rails.root.join('config/database.yml').read).result

      expect(YAML.safe_load(yaml, aliases: true).dig('production', 'sslca')).to be_nil
    end
  end

  def configuration_for(url)
    ActiveRecord::DatabaseConfigurations.new(
      'production' => { 'adapter' => 'mysql2', 'url' => url, 'ssl_mode' => 'verify_identity' }
    ).configs_for(env_name: 'production', name: 'primary').configuration_hash
  end

  it 'requires certificate and hostname verification when the URL has no TLS options' do
    configuration = configuration_for('mysql2://example:example@db.example:3306/app')

    expect(configuration[:ssl_mode]).to eq('verify_identity')
    expect { described_class.validate!(configuration) }.not_to raise_error
  end

  it 'keeps verification enabled when a provider URL contains the unrecognized ssl-mode option' do
    configuration = configuration_for('mysql2://example:example@db.example:3306/app?ssl-mode=REQUIRED')

    expect(configuration[:ssl_mode]).to eq('verify_identity')
    expect { described_class.validate!(configuration) }.not_to raise_error
  end

  %w[disabled preferred required verify_ca invalid].each do |weak_mode|
    it "rejects a URL that overrides verification with #{weak_mode}" do
      configuration = configuration_for("mysql2://example:example@db.example:3306/app?ssl_mode=#{weak_mode}")

      expect { described_class.validate!(configuration) }.to raise_error(described_class::ConfigurationError)
    end
  end

  it 'accepts a readable provider CA file' do
    Tempfile.create('gatareview-test-ca') do |file|
      expect { described_class.validate!(ssl_mode: 'verify_identity', sslca: file.path) }.not_to raise_error
    end
  end

  it 'rejects a missing provider CA file' do
    expect do
      described_class.validate!(ssl_mode: 'verify_identity', sslca: '/nonexistent/gatareview-ca.pem')
    end.to raise_error(described_class::ConfigurationError)
  end
end
