# frozen_string_literal: true

module Syllabus
  class ImportRollback
    Error = Class.new(StandardError)

    Result = Struct.new(:run, :restored_rows, keyword_init: true)

    def initialize(import_run_id:, confirm:, now: Time.current)
      @run = SyllabusImportRun.find(import_run_id)
      @confirm = confirm
      @now = now
    end

    def call
      validate!
      @rollback_status = run.status
      protected_counts = domain_counts
      restored_rows = 0

      SyllabusImportRun.transaction do
        SyllabusImportRun.where(year: run.year).lock.load
        run.lock!
        validate!
        @rollback_status = run.status

        run.syllabus_import_rows.order(sequence_number: :desc).each do |row|
          rollback_row!(row)
          restored_rows += 1
        end

        raise Error, 'Review・Bookmark・TimetableEntryの件数がrollback中に変化しました' unless domain_counts == protected_counts

        run.update!(status: 'rolled_back', rolled_back_at: now, finished_at: now)
      end

      Result.new(run: run.reload, restored_rows:)
    rescue StandardError => e
      raise e if e.is_a?(Error)

      raise Error, e.message
    end

    private

    attr_reader :run, :confirm, :now

    def validate!
      raise Error, 'CONFIRM=true が必要です' unless confirm
      raise Error, "rollbackできないrunです: status=#{run.status}" unless run.applied_to_domain?

      later_run = SyllabusImportRun.applied_to_domain.where(year: run.year).where('applied_at > ?', run.applied_at).exists?
      raise Error, '同年度に後続の適用済みrunがあるためrollbackできません' if later_run
    end

    def rollback_row!(row)
      case row.action
      when 'create_offering', 'create_lecture_and_offering'
        destroy_created_offering!(row)
      when 'update_offering', 'unchanged'
        restore_offering!(row)
      when 'mark_missing'
        restore_offering!(row) unless @rollback_status == 'applied_without_missing'
      when 'create_lecture', 'lecture_unchanged'
        nil
      end
    end

    def destroy_created_offering!(row)
      offering = LectureOffering.lock.find_by(id: row.matched_offering_id)
      return unless offering

      ensure_applied_snapshot!(offering, row)

      review_ids = offering.reviews.lock.pluck(:id)
      timetable_entry_ids = offering.timetable_entries.lock.pluck(:id)
      detail_id = offering.lecture_offering_detail&.id
      if review_ids.any? || timetable_entry_ids.any? || detail_id
        raise Error,
              "作成したOfferingが参照されているためrollbackできません: offering=#{offering.id}, " \
              "reviews=#{review_ids.join(',')}, timetable_entries=#{timetable_entry_ids.join(',')}, " \
              "detail=#{detail_id}"
      end

      offering.destroy!
    end

    def restore_offering!(row)
      return if row.before_values.blank?

      offering = LectureOffering.lock.find_by(id: row.matched_offering_id)
      raise Error, "復元対象Offeringが見つかりません: #{row.matched_offering_id}" unless offering
      ensure_applied_snapshot!(offering, row)

      values = row.before_values.deep_dup
      slots = values.delete('slots') || []
      offering.update!(values.slice(
        'lecture_id', 'year', 'registration_code', 'shozoku_code', 'syllabus_organization_id',
        'semester_label', 'term_label', 'term_code', 'source_title', 'source_lecturer',
        'source_faculty', 'raw_day_periods', 'schedule_kind', 'source_status', 'source_checksum',
        'first_seen_import_run_id', 'last_seen_import_run_id', 'missing_since_import_run_id'
      ))
      offering.offering_slots.delete_all
      slots.each { |slot| offering.offering_slots.create!(day: slot.fetch('day'), period: slot.fetch('period')) }
    end

    def ensure_applied_snapshot!(offering, row)
      return if OfferingSnapshot.matches_for_update?(offering, expected_applied_snapshot(row))

      raise Error,
            "Offeringがrun適用後から変更されているためrollbackできません: " \
            "row=#{row.sequence_number}, offering=#{offering.id}"
    end

    def expected_applied_snapshot(row)
      before = row.before_values.to_h.deep_stringify_keys
      values = if %w[create_offering create_lecture_and_offering update_offering].include?(row.action)
                 row.after_values.to_h.deep_stringify_keys
               else
                 before.deep_dup
               end

      values['lecture_id'] = row.matched_lecture_id
      case row.action
      when 'create_offering', 'create_lecture_and_offering'
        values['first_seen_import_run_id'] = run.id
        values['last_seen_import_run_id'] = run.id
        values['missing_since_import_run_id'] = nil
      when 'update_offering'
        values['first_seen_import_run_id'] = before['first_seen_import_run_id'] || run.id
        values['last_seen_import_run_id'] = run.id
        values['missing_since_import_run_id'] = nil
      when 'unchanged'
        values['first_seen_import_run_id'] = before['first_seen_import_run_id'] || run.id
        values['last_seen_import_run_id'] = run.id
        values['source_status'] = 'active'
        values['missing_since_import_run_id'] = nil
      when 'mark_missing'
        values['source_status'] = 'missing'
        values['missing_since_import_run_id'] = before['missing_since_import_run_id'] || run.id
      end
      values
    end

    def domain_counts
      {
        reviews: Review.count,
        bookmarks: Bookmark.count,
        timetable_entries: defined?(TimetableEntry) && TimetableEntry.table_exists? ? TimetableEntry.count : 0
      }
    end
  end
end
