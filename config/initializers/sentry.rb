# frozen_string_literal: true

require Rails.root.join('lib/monitoring/sentry_privacy')

Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.environment = Rails.env
  config.enabled_environments = %w[production]
  config.release = ENV['HEROKU_SLUG_COMMIT']
  config.traces_sample_rate = 0.0
  config.propagate_traces = false
  config.auto_session_tracking = false
  config.breadcrumbs_logger = []
  config.max_breadcrumbs = 0
  config.before_send = ->(event, hint) { Monitoring::SentryPrivacy.scrub(event, hint) }
  config.before_send_log = ->(_log) { nil }
  config.before_send_metric = ->(_metric) { nil }

  data = config.data_collection
  data.user_info = false
  data.cookies = false
  data.http_headers.request = false
  data.http_headers.response = false
  data.http_bodies = []
  data.url_query_params = false
  data.database_query_data = false
  data.queues = false
  data.stack_frame_variables = false
  data.frame_context_lines = 0
  data.graphql.document = false
  data.graphql.variables = false
end
