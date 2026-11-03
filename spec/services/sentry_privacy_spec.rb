# frozen_string_literal: true

require 'spec_helper'
require 'sentry-ruby'
require_relative '../../lib/monitoring/sentry_privacy'

RSpec.describe Monitoring::SentryPrivacy do
  before do
    Sentry.init do |config|
      config.dsn = 'https://public@o123.ingest.us.sentry.io/456'
      config.environment = 'test'
      config.background_worker_threads = 0
      config.transport.transport_class = Sentry::DummyTransport
      config.before_send = described_class.method(:scrub)
    end
  end

  after { Sentry.close }

  it 'sends error type and code location without submitted data or identity' do
    marker = 'PRIVATE_REVIEW_EMAIL_TOKEN'
    exception = ArgumentError.new(marker)
    exception.set_backtrace(['/app/app/controllers/api/v1/reviews_controller.rb:12:in `create\''])
    Sentry.with_scope do |scope|
      scope.set_user(email: marker, ip_address: marker)
      scope.set_extras(review: marker, sql: marker)
      scope.set_tags(token: marker)
      Sentry.capture_exception(exception)
    end

    transport = Sentry.get_current_client.transport
    sent = transport.events.last
    serialized, = transport.serialize_envelope(transport.envelope_from_event(sent))
    expect(JSON.parse(serialized.lines[1])['type']).to eq('event')
    expect(serialized).not_to include(marker)
    event = sent.to_h
    expect(event.to_json).not_to include(marker)
    expect(event.dig(:exception, :values, 0, :type)).to eq('ArgumentError')
    expect(event.dig(:exception, :values, 0, :stacktrace, :frames, 0, :lineno)).to eq(12)
  end

  it 'drops request fields, attachments, source context and new unknown SDK fields' do
    marker = 'PRIVATE_REQUEST_COOKIE_TOKEN'
    event = Sentry.get_current_client.event_from_exception(StandardError.new(marker))
    payload = event.to_h.merge(
      request: { data: marker, headers: { Authorization: marker }, cookies: marker },
      threads: marker, new_sdk_field: marker,
      exception: { values: [{ type: 'StandardError', value: marker, stacktrace: { frames: [{
        filename: "/app/controllers/reviews_controller.rb?token=#{marker}", lineno: 8,
        context_line: marker, vars: { token: marker }
      }] } }] }
    )
    allow(event).to receive(:to_h).and_return(payload)

    result = described_class.scrub(event, {})
    expect(result).to be_a(Sentry::ErrorEvent)
    expect(result.to_h.to_json).not_to include(marker)
    expect(result.attachments).to be_empty
    expect(result.dynamic_sampling_context).to be_nil
    expect(result.to_h.dig(:exception, :values, 0, :stacktrace, :frames, 0, :lineno)).to eq(8)
  end
end
