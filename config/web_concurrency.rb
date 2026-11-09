# frozen_string_literal: true

# Number of Puma worker processes. Shared by config/puma.rb and the rate limiter
# (config/initializers/rack_attack.rb), which divides its limits by this number
# because every worker keeps its own in-memory counters.
module WebConcurrency
  DEFAULT_WORKERS = 2

  def self.workers(env = ENV)
    Integer(env['WEB_CONCURRENCY'] || DEFAULT_WORKERS)
  end
end
