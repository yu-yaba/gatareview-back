# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe 'Rate limit counter store and per-worker limits', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:production) { ActiveSupport::EnvironmentInquirer.new('production') }

  it 'uses an in-process MemoryStore outside the test environment instead of the FileStore default' do
    %w[production development].each do |name|
      store = RateLimitSettings.cache_store(ActiveSupport::EnvironmentInquirer.new(name))

      expect(store).to be_a(ActiveSupport::Cache::MemoryStore)
      expect(store).not_to be_a(ActiveSupport::Cache::FileStore)
    end
  end

  it 'counts concurrent requests exactly with the production store' do
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = RateLimitSettings.cache_store(production)
    app = Rack::Attack.new(->(_env) { [200, {}, ['ok']] })
    limit = Rack::Attack::API_LIMIT_PER_WORKER
    work = Queue.new
    (limit * 3).times { work << true }
    work.close
    statuses = Queue.new

    travel_to(Time.utc(2026, 11, 9, 3, 10, 10)) do
      Array.new(16) do
        Thread.new do
          client = Rack::MockRequest.new(app)
          statuses << client.get('/api/v1/lectures', 'REMOTE_ADDR' => '192.0.2.150').status while work.pop
        end
      end.each(&:join)
    end
    results = Array.new(statuses.size) { statuses.pop }

    expect(results.count(200)).to eq(limit)
    expect(results.count(429)).to eq(limit * 2)
  ensure
    Rack::Attack.cache.store = original_store
  end

  it 'divides each limit by the number of Puma workers, rounding up' do
    expect(RateLimitSettings.per_worker(10, workers: 2)).to eq(5)
    expect(RateLimitSettings.per_worker(300, workers: 2)).to eq(150)
    expect(RateLimitSettings.per_worker(10, workers: 3)).to eq(4)
    expect(RateLimitSettings.per_worker(1, workers: 4)).to eq(1)
    expect(RateLimitSettings.per_worker(10, workers: 1)).to eq(10)
    expect(RateLimitSettings.per_worker(10, workers: 0)).to eq(10)
  end

  it 'reads the worker count from the same source as config/puma.rb' do
    expect(WebConcurrency.workers({})).to eq(2)
    expect(WebConcurrency.workers('WEB_CONCURRENCY' => '3')).to eq(3)
    expect(Rails.root.join('config/puma.rb').read).to include('workers WebConcurrency.workers')
  end

  it 'configures the throttles with the per-worker limits' do
    workers = WebConcurrency.workers

    expect(Rack::Attack::AUTH_LIMIT_PER_WORKER).to eq((Rack::Attack::AUTH_LIMIT.to_f / workers).ceil)
    expect(Rack::Attack::API_LIMIT_PER_WORKER).to eq((Rack::Attack::API_LIMIT.to_f / workers).ceil)
    expect(Rack::Attack.throttles['auth/google/ip'].limit).to eq(Rack::Attack::AUTH_LIMIT_PER_WORKER)
    expect(Rack::Attack.throttles['api/ip'].limit).to eq(Rack::Attack::API_LIMIT_PER_WORKER)
  end

  it 'boots production with a MemoryStore and limits scaled by WEB_CONCURRENCY' do
    env = {
      'RAILS_ENV' => 'production',
      'SECRET_KEY_BASE_DUMMY' => '1',
      'WEB_CONCURRENCY' => '4',
      'AUTH_RATE_LIMIT_PER_MINUTE' => nil,
      'API_RATE_LIMIT_PER_FIVE_MINUTES' => nil,
      'RAILS_LOG_TO_STDOUT' => nil,
      'DYNO' => nil
    }
    script = 'puts ["RESULT", Rack::Attack.cache.store.class, ' \
             'Rack::Attack.throttles.transform_values(&:limit).sort.to_h.to_json].join(" ")'

    output, status = Open3.capture2e(env, 'bin/rails', 'runner', script, chdir: Rails.root.to_s)

    expect(status).to be_success, output
    expect(output).to include('RESULT ActiveSupport::Cache::MemoryStore {"api/ip":75,"auth/google/ip":3}')
  end
end
