# frozen_string_literal: true

require 'rails_helper'
require 'erb'
require 'yaml'

RSpec.describe 'Production database connection reuse' do
  # These read-only checks need real checkin/checkout, without fixture pinning.
  self.use_transactional_tests = false

  let(:production_config) do
    YAML.safe_load(ERB.new(Rails.root.join('config/database.yml').read).result, aliases: true).fetch('production')
  end
  let(:record_class) { Class.new(ActiveRecord::Base) { self.abstract_class = true } }
  let(:pool) { record_class.connection_pool }

  before do
    stub_const('ConnectionReuseRecord', record_class)
    record_class.establish_connection(
      ActiveRecord::Base.connection_db_config.configuration_hash.merge(
        idle_timeout: production_config.fetch('idle_timeout'), reaping_frequency: nil
      )
    )
  end

  after { record_class.remove_connection }

  it 'keeps the existing thread-based pool limit and TLS identity verification' do
    expect(production_config.fetch('pool')).to eq(ENV.fetch('RAILS_MAX_THREADS', '5').to_i)
    expect(production_config.fetch('ssl_mode')).to eq('verify_identity')
    expect(pool.min_connections).to eq(0)
  end

  it 'reuses a connection after ten idle minutes and releases it after thirty minutes' do
    connection = pool.checkout
    first_id = connection.select_value('SELECT CONNECTION_ID()')
    pool.checkin(connection)
    allow(connection).to receive(:seconds_idle).and_return(600)
    pool.flush
    expect(pool.connections).to include(connection)
    pool.with_connection { |reused| expect(reused.select_value('SELECT CONNECTION_ID()')).to eq(first_id) }

    allow(connection).to receive(:seconds_idle).and_return(1801)
    pool.flush
    expect(pool.connections).to be_empty
    pool.with_connection { |fresh| expect(fresh.select_value('SELECT CONNECTION_ID()')).not_to eq(first_id) }
  end

  it 'recovers when an idle database connection has been closed' do
    first_id = pool.with_connection do |connection|
      id = connection.select_value('SELECT CONNECTION_ID()')
      connection.raw_connection.close
      id
    end
    pool.keep_alive(0)
    pool.with_connection do |connection|
      expect(connection.select_value('SELECT 1')).to eq(1)
      expect(connection.select_value('SELECT CONNECTION_ID()')).not_to eq(first_id)
    end
  end
end
