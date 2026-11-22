# frozen_string_literal: true

require 'rails_helper'
require 'erb'
require 'yaml'
require Rails.root.join('lib/database_warm_up').to_s

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
        max_connections: production_config.fetch('max_connections'),
        min_connections: production_config.fetch('min_connections'),
        idle_timeout: production_config.fetch('idle_timeout'), reaping_frequency: nil
      )
    )
  end

  after { record_class.remove_connection }

  def backend_pid(connection)
    connection.select_value('SELECT pg_backend_pid()')
  end

  it 'keeps the thread-based limit, two warm connections and TLS identity verification' do
    expect(production_config.fetch('max_connections')).to eq(ENV.fetch('RAILS_MAX_THREADS', '5').to_i)
    expect(production_config.fetch('min_connections')).to eq(ENV.fetch('DB_MIN_CONNECTIONS', '2').to_i)
    expect(production_config).not_to have_key('pool')
    expect(production_config.fetch('sslmode')).to eq('verify-full')
    expect(pool.min_connections).to eq(2)
  end

  it 'opens up to the minimum connections when the reaper prepopulates a warmed-up pool' do
    # config/puma.rb の before_worker_boot と同じ処理（DatabaseWarmUp）のあと、reaper が呼ぶ prepopulate を直接呼ぶ。
    # Puma と reaper を通した動作は、本番設定の Puma を起動して pg_stat_activity で確かめた（PR に記載）。
    expect(DatabaseWarmUp.call(pool: pool, output: StringIO.new)).to be(true)

    pool.prepopulate

    expect(pool.connections.size).to eq(2)
    expect(pool.connections.map { |connection| backend_pid(connection) }.uniq.size).to eq(2)
  end

  it 'still lets the reaper open the minimum connections when the database was unreachable at boot' do
    output = StringIO.new
    adapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    calls = 0
    allow_any_instance_of(adapter).to receive(:verify!).and_wrap_original do |original, *args|
      calls += 1
      raise ActiveRecord::ConnectionNotEstablished, 'database is down' if calls == 1

      original.call(*args)
    end
    allow(Rails.error).to receive(:report)

    expect(DatabaseWarmUp.call(pool: pool, output: output)).to be(false)
    expect(output.string).to include('ActiveRecord::ConnectionNotEstablished: database is down')
    expect(Rails.error).to have_received(:report).with(instance_of(ActiveRecord::ConnectionNotEstablished),
                                                       hash_including(handled: true))

    # DB が戻ったあとの reaper の動き（prepopulate と preconnect）を再現する。
    pool.prepopulate
    pool.preconnect

    # 接続の数ではなく、実際に DB とつながっている本数を数える。
    expect(pool.connections.count(&:connected?)).to eq(2)
    expect(pool.connections.map { |connection| backend_pid(connection) }.uniq.size).to eq(2)
  end

  it 'is what Puma runs when each worker boots' do
    expect(Rails.root.join('config/puma.rb').read).to match(/before_worker_boot do.*DatabaseWarmUp\.call/m)
  end

  it 'keeps the minimum connections after thirty idle minutes and closes only the extra ones' do
    connections = Array.new(3) { pool.checkout }
    pids = connections.map { |connection| backend_pid(connection) }
    connections.each do |connection|
      pool.checkin(connection)
      allow(connection).to receive(:seconds_idle).and_return(1801)
    end

    pool.flush

    expect(pool.connections.size).to eq(2)
    pool.with_connection { |reused| expect(pids).to include(backend_pid(reused)) }
  end

  it 'reuses an idle connection after ten minutes' do
    connection = pool.checkout
    first_id = backend_pid(connection)
    pool.checkin(connection)
    allow(connection).to receive(:seconds_idle).and_return(600)

    pool.flush

    pool.with_connection { |reused| expect(backend_pid(reused)).to eq(first_id) }
  end

  it 'recovers when an idle database connection has been closed' do
    first_id = pool.with_connection do |connection|
      id = backend_pid(connection)
      connection.raw_connection.close
      id
    end
    pool.keep_alive(0)
    pool.with_connection do |connection|
      expect(connection.select_value('SELECT 1')).to eq(1)
      expect(backend_pid(connection)).not_to eq(first_id)
    end
  end
end
