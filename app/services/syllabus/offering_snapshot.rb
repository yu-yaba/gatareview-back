# frozen_string_literal: true

module Syllabus
  module OfferingSnapshot
    ATTRIBUTES = %w[
      lecture_id
      year
      registration_code
      shozoku_code
      syllabus_organization_id
      semester_label
      term_label
      term_code
      source_title
      source_lecturer
      source_faculty
      raw_day_periods
      schedule_kind
      source_status
      source_checksum
      first_seen_import_run_id
      last_seen_import_run_id
      missing_since_import_run_id
    ].freeze

    module_function

    def capture(offering)
      capture_with_slots(offering, slot_values(offering, lock: false))
    end

    def matches_for_update?(offering, expected)
      return false if expected.blank?

      capture_for_update(offering) == normalize(expected)
    end

    def capture_for_update(offering)
      unless OfferingSlot.connection.transaction_open?
        raise ArgumentError, 'OfferingSlotのsnapshot lockはtransaction内で実行してください'
      end

      capture_with_slots(offering, slot_values(offering, lock: true))
    end

    def capture_with_slots(offering, slots)
      offering.attributes.slice(*ATTRIBUTES).merge(
        'slots' => slots.map do |day, period|
          { 'day' => day, 'period' => period }
        end
      )
    end

    def slot_values(offering, lock:)
      scope = OfferingSlot.where(lecture_offering_id: offering.id).order(:day, :period)
      scope = scope.lock if lock

      scope.pluck(:day, :period)
    end

    def normalize(snapshot)
      values = snapshot.deep_stringify_keys
      values['slots'] = Array(values['slots']).sort_by { |slot| [slot.fetch('day'), slot.fetch('period')] }
      values
    end

    private_class_method :capture_for_update, :capture_with_slots, :slot_values
  end
end
