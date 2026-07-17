# frozen_string_literal: true

module Syllabus
  class ImportApplier
    Error = Class.new(StandardError)

    Result = Struct.new(:run, :applied_rows, :skipped_missing_rows, keyword_init: true)

    def initialize(import_run_id:, confirm:, confirm_missing: false, now: -> { Time.current })
      @run = SyllabusImportRun.find(import_run_id)
      @confirm = confirm
      @confirm_missing = confirm_missing
      @clock = now.respond_to?(:call) ? now : -> { now }
    end

    def call
      @original_status = run.status
      validate!
      @started_application = true
      protected_counts = domain_counts
      applied_rows = 0
      skipped_missing_rows = 0

      SyllabusImportRun.transaction do
        SyllabusImportRun.where(year: run.year).lock.load
        run.lock!
        @original_status = run.status
        validate!
        @completing_missing = run.missing_completion_pending?
        @operation_time = next_application_time
        run.update!(status: 'applying', finished_at: nil)

        run.syllabus_import_rows.order(:sequence_number).each do |row|
          if completing_missing
            next unless row.action == 'mark_missing'
          elsif row.action == 'mark_missing' && !confirm_missing
            skipped_missing_rows += 1
            next
          end

          apply_row!(row)
          applied_rows += 1
        end

        raise Error, 'Review・Bookmark・TimetableEntryの件数が適用中に変化しました' unless domain_counts == protected_counts

        final_status = skipped_missing_rows.positive? ? 'applied_without_missing' : 'applied'
        run.update!(status: final_status, applied_at: operation_time, finished_at: operation_time, error_summary: nil)
      end

      Result.new(run: run.reload, applied_rows:, skipped_missing_rows:)
    rescue StandardError => e
      record_failure!(e) if run.persisted?
      raise e if e.is_a?(Error)

      raise Error, e.message
    end

    private

    attr_reader :run, :confirm, :confirm_missing, :clock, :operation_time

    def completing_missing
      @completing_missing
    end

    def validate!
      raise Error, 'CONFIRM=true が必要です' unless confirm
      unless run.applicable? || (run.missing_completion_pending? && confirm_missing)
        raise Error, "適用できないrunです: status=#{run.status}"
      end
      raise Error, '解析結果のハッシュが一致しません' unless run.staged_sha256.present? && run.calculated_staged_sha256 == run.staged_sha256

      duplicated = SyllabusImportRun.applied_to_domain.where(year: run.year, source_sha256: run.source_sha256).where.not(id: run.id).exists?
      raise Error, '同じ年度・同じCSVは既に適用済みです' if duplicated

      return unless run.missing_completion_pending?

      later_run = SyllabusImportRun.applied_to_domain.where(year: run.year).where('applied_at > ?', run.applied_at).exists?
      raise Error, '同年度に後続の適用済みrunがあるため未掲載差分を適用できません' if later_run
    end

    def apply_row!(row)
      case row.action
      when 'create_lecture'
        lecture = create_lecture!(row)
        row.update_columns(matched_lecture_id: lecture.id)
      when 'lecture_unchanged'
        ensure_lecture!(row)
      when 'create_lecture_and_offering'
        lecture = create_lecture!(row)
        offering = create_offering!(row, lecture)
        row.update_columns(matched_lecture_id: lecture.id, matched_offering_id: offering.id)
      when 'create_offering'
        lecture = ensure_lecture!(row)
        offering = create_offering!(row, lecture)
        row.update_columns(matched_offering_id: offering.id)
      when 'update_offering'
        update_offering!(row)
      when 'unchanged'
        touch_last_seen!(row)
      when 'mark_missing'
        mark_missing!(row)
      when 'conflict', 'error'
        raise Error, "適用不能な行が含まれています: row=#{row.sequence_number}, action=#{row.action}"
      else
        raise Error, "未知のactionです: #{row.action}"
      end
    end

    def create_lecture!(row)
      existing = Lecture.canonical.find_by(normalized_key: row.normalized_key)
      return existing if existing

      Lecture.create!(title: row.source_title, lecturer: row.source_lecturer, faculty: row.source_faculty)
    end

    def ensure_lecture!(row)
      lecture = Lecture.canonical.find_by(id: row.matched_lecture_id)
      raise Error, "照合済みLectureが見つかりません: #{row.matched_lecture_id}" unless lecture
      raise Error, "Lectureのnormalized_keyが解析時から変わっています: #{lecture.id}" unless lecture.normalized_key == row.normalized_key

      lecture
    end

    def create_offering!(row, lecture)
      attributes = offering_attributes(row).merge(
        lecture:,
        first_seen_import_run: run,
        last_seen_import_run: run,
        missing_since_import_run: nil
      )
      offering = LectureOffering.create!(attributes)
      replace_slots!(offering, row.after_values.fetch('slots', []))
      offering
    end

    def update_offering!(row)
      offering = LectureOffering.lock.find(row.matched_offering_id)
      raise Error, "既存Offeringのlecture_idが解析時から変わっています: #{offering.id}" unless offering.lecture_id == row.matched_lecture_id
      ensure_snapshot!(offering, row)

      attributes = offering_attributes(row).merge(
        first_seen_import_run_id: offering.first_seen_import_run_id || run.id,
        last_seen_import_run: run,
        missing_since_import_run: nil
      )
      offering.update!(attributes)
      replace_slots!(offering, row.after_values.fetch('slots', []))
    end

    def touch_last_seen!(row)
      offering = LectureOffering.lock.find(row.matched_offering_id)
      raise Error, "既存Offeringのlecture_idが解析時から変わっています: #{offering.id}" unless offering.lecture_id == row.matched_lecture_id
      ensure_snapshot!(offering, row)

      offering.update_columns(
        last_seen_import_run_id: run.id,
        first_seen_import_run_id: offering.first_seen_import_run_id || run.id,
        source_status: 'active',
        missing_since_import_run_id: nil
      )
    end

    def mark_missing!(row)
      offering = LectureOffering.lock.find(row.matched_offering_id)
      raise Error, "既存Offeringのlecture_idが解析時から変わっています: #{offering.id}" unless offering.lecture_id == row.matched_lecture_id
      ensure_snapshot!(offering, row)

      offering.update_columns(
        source_status: 'missing',
        missing_since_import_run_id: offering.missing_since_import_run_id || run.id,
        updated_at: operation_time
      )
    end

    def ensure_snapshot!(offering, row)
      return if OfferingSnapshot.matches_for_update?(offering, row.before_values)

      raise Error,
            "Offeringが解析時から変更されているため再解析が必要です: " \
            "row=#{row.sequence_number}, offering=#{offering.id}"
    end

    def next_application_time
      candidate = clock.call
      latest = SyllabusImportRun.where(year: run.year).where.not(applied_at: nil).maximum(:applied_at)
      return candidate unless latest

      # 現行DBのDATETIME精度は秒のため、同秒の適用でも必ず全順序が残るようにする
      [candidate, latest + 1.second].max
    end

    def record_failure!(error)
      current_status = run.reload.status
      if @original_status == 'applied_without_missing' && current_status == 'applied_without_missing'
        run.update_columns(error_summary: error.message, finished_at: Time.current)
      elsif @started_application && !%w[applied_without_missing applied rolled_back].include?(current_status)
        run.update_columns(status: 'failed', error_summary: error.message, finished_at: Time.current)
      end
    end

    def offering_attributes(row)
      values = row.after_values.deep_dup
      values.delete('slots')
      values.slice(
        'year', 'registration_code', 'shozoku_code', 'syllabus_organization_id',
        'semester_label', 'term_label', 'term_code', 'source_title', 'source_lecturer',
        'source_faculty', 'raw_day_periods', 'schedule_kind', 'source_status', 'source_checksum'
      )
    end

    def replace_slots!(offering, slots)
      offering.offering_slots.delete_all
      slots.each do |slot|
        offering.offering_slots.create!(day: slot.fetch('day'), period: slot.fetch('period'))
      end
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
