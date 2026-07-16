# frozen_string_literal: true

module Syllabus
  class ScheduleParser
    Result = Struct.new(:raw, :kind, :slots, :error, keyword_init: true)

    INTENSIVE_LABELS = %w[集中 集中講義].freeze
    OTHER_LABELS = %w[他 その他 時間外 年度跨り].freeze

    def self.call(value, term_code:)
      raw = Normalizer.text(value)
      normalized = raw.tr('０１２３４５６７', '01234567')
      slots = normalized.scan(/([月火水木金土日])\s*([1-7])/)
                        .map { |day, period| [OfferingSlot::DAYS.fetch(day), period.to_i] }
                        .uniq

      return Result.new(raw:, kind: 'regular', slots:) if slots.any?
      return Result.new(raw:, kind: 'intensive', slots: []) if INTENSIVE_LABELS.include?(normalized) || term_code == '4'
      return Result.new(raw:, kind: 'other', slots: []) if OTHER_LABELS.include?(normalized) || %w[5 9].include?(term_code)

      if raw.blank?
        return Result.new(raw:, kind: 'unknown', slots: [], error: '曜日・時限が空で、集中・その他の区分でもありません')
      end

      Result.new(raw:, kind: 'unknown', slots: [], error: "曜日・時限を解析できません: #{raw}")
    end
  end
end
