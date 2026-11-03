# frozen_string_literal: true

module Monitoring
  module SentryPrivacy
    MESSAGE = 'Unexpected application error'
    EVENT_FIELDS = %i[event_id timestamp platform level environment release sdk].freeze

    # Sentry requires before_send to return an ErrorEvent. Serialize only the
    # allowed payload, so newly added SDK fields cannot leak request contents.
    class FilteredEvent < Sentry::ErrorEvent
      def initialize(source, payload)
        super(configuration: Sentry.configuration)
        self.event_id = source.event_id
        @payload = payload
      end

      def to_h
        @payload
      end
    end

    def self.scrub(event, _hint)
      data = event.to_h
      payload = data.slice(*EVENT_FIELDS).merge(type: 'event', message: MESSAGE, tags: { service: 'gatareview-back' })
      payload[:exception] = { values: data[:exception][:values].map { |value| safe_exception(value) } } if data[:exception]
      FilteredEvent.new(event, payload)
    end

    def self.safe_exception(value)
      result = { type: identifier(value[:type]) || 'Error', value: MESSAGE }
      result[:stacktrace] = { frames: value[:stacktrace][:frames].map { |frame| safe_frame(frame) } } if value[:stacktrace]
      result
    end

    def self.safe_frame(frame)
      result = frame.slice(:lineno, :colno, :in_app)
      result[:function] = identifier(frame[:function])
      result[:filename] = frame[:filename]&.split(/[?#]/)&.first&.tr('\\', '/')&.split('/')&.last(3)&.join('/')
      result
    end

    def self.identifier(value)
      value if value.is_a?(String) && value.match?(/\A[\w.$<>\[\] :()-]{1,120}\z/)
    end
  end
end
