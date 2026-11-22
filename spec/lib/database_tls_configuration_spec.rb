# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe DatabaseTlsConfiguration do
  def production_yaml_with(ca_path)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('DATABASE_SSL_CA').and_return(ca_path)
    YAML.safe_load(ERB.new(Rails.root.join('config/database.yml').read).result, aliases: true).fetch('production')
  end

  it 'leaves sslrootcert empty when DATABASE_SSL_CA is absent or empty, so boot is refused' do
    [nil, ''].each do |ca_path|
      configuration = production_yaml_with(ca_path)

      expect(configuration).to include('sslmode' => 'verify-full', 'sslrootcert' => '')
      expect { described_class.validate!(configuration.symbolize_keys) }
        .to raise_error(described_class::ConfigurationError, /DATABASE_SSL_CA/)
    end
  end

  it 'rejects sslrootcert=system because the bundled libpq does not read the OS CA store' do
    expect { described_class.validate!(sslmode: 'verify-full', sslrootcert: 'system') }
      .to raise_error(described_class::ConfigurationError, /DATABASE_SSL_CA/)
  end

  it 'uses the provider CA file when DATABASE_SSL_CA is set' do
    expect(production_yaml_with('/app/config/certs/aiven-ca.pem'))
      .to include('sslrootcert' => '/app/config/certs/aiven-ca.pem')
  end

  let(:ca_file) { Tempfile.create('gatareview-test-ca') }

  after { File.unlink(ca_file.path) if File.exist?(ca_file.path) }

  def configuration_for(url)
    ActiveRecord::DatabaseConfigurations.new(
      'production' => { 'adapter' => 'postgresql', 'url' => url, 'sslmode' => 'verify-full', 'sslrootcert' => ca_file.path }
    ).configs_for(env_name: 'production', name: 'primary').configuration_hash
  end

  it 'requires certificate and hostname verification when the URL has no TLS options' do
    configuration = configuration_for('postgres://example:example@db.example:5432/app')

    expect(configuration[:sslmode]).to eq('verify-full')
    expect { described_class.validate!(configuration) }.not_to raise_error
  end

  it 'accepts a URL that asks for verify-full itself' do
    configuration = configuration_for('postgres://example:example@db.example:5432/app?sslmode=verify-full')

    expect { described_class.validate!(configuration) }.not_to raise_error
  end

  %w[disable allow prefer require verify-ca invalid].each do |weak_mode|
    it "rejects a URL that overrides verification with #{weak_mode}" do
      configuration = configuration_for("postgres://example:example@db.example:5432/app?sslmode=#{weak_mode}")

      expect { described_class.validate!(configuration) }
        .to raise_error(described_class::ConfigurationError, /verify-full/)
    end
  end

  it 'accepts a readable provider CA file' do
    Tempfile.create('gatareview-test-ca') do |file|
      expect { described_class.validate!(sslmode: 'verify-full', sslrootcert: file.path) }.not_to raise_error
    end
  end

  it 'rejects a missing provider CA file' do
    expect do
      described_class.validate!(sslmode: 'verify-full', sslrootcert: '/nonexistent/gatareview-ca.pem')
    end.to raise_error(described_class::ConfigurationError)
  end
end
