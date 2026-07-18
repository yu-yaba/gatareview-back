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
      applied_rows = 0
      skipped_missing_rows = 0

      SyllabusImportRun.transaction do
        SyllabusImportRun.where(year: run.year).lock.load
        run.lock!
        rows = run.syllabus_import_rows.order(:sequence_number).lock.to_a
        @original_status = run.status
        validate!(rows:)
        @completing_missing = run.missing_completion_pending?
        @operation_time = next_application_time
        run.update!(status: 'applying', finished_at: nil)

        rows.each do |row|
          if completing_missing
            next unless row.action == 'mark_missing'
          elsif row.action == 'mark_missing' && !confirm_missing
            skipped_missing_rows += 1
            next
          end

          apply_row!(row)
          applied_rows += 1
        end

        offering_ids = rows.filter_map { |row| row.applied_offering_id || row.matched_offering_id }
        unless DomainReferenceIntegrity.valid_for_offerings?(offering_ids)
          raise Error, 'Review・TimetableEntryと対象Offeringの参照整合性が適用中に崩れました'
        end

        final_status = skipped_missing_rows.positive? ? 'applied_without_missing' : 'applied'
        run.update!(
          status: final_status,
          applied_at: operation_time,
          finished_at: operation_time,
          error_summary: nil,
          applied_result_sha256: run.calculated_applied_result_sha256(rows:)
        )
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

    def validate!(rows: nil)
      raise Error, 'CONFIRM=true が必要です' unless confirm
      unless run.applicable? || (run.missing_completion_pending? && confirm_missing)
        raise Error, "適用できないrunです: status=#{run.status}"
      end
      if run.staged_payload_version.to_i < SyllabusImportRun::STAGED_PAYLOAD_VERSION
        message = if run.missing_completion_pending?
                    '旧形式で未掲載差分を保留したrunは完了できません。' \
                      'このrunをrollbackしてからCSVを再解析・再適用してください'
                  else
                    '旧形式の解析結果は適用できません。CSVを再解析してください'
                  end
        raise Error, message
      end
      unless run.staged_sha256.present? && run.calculated_staged_sha256(rows:) == run.staged_sha256
        raise Error, '解析結果のハッシュが一致しません'
      end
      if run.staged_payload_version.to_i >= SyllabusImportRun::STAGED_PAYLOAD_VERSION &&
         run.missing_completion_pending? &&
         (run.applied_result_sha256.blank? || run.calculated_applied_result_sha256(rows:) != run.applied_result_sha256)
        raise Error, '適用結果のハッシュが一致しません'
      end

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
        record_applied_result!(row, lecture:)
      when 'lecture_unchanged'
        lecture = ensure_lecture!(row)
        record_applied_result!(row, lecture:)
      when 'create_lecture_and_offering'
        lecture = create_lecture!(row)
        offering = create_offering!(row, lecture)
        record_applied_result!(row, lecture:, offering:)
      when 'create_offering'
        lecture = ensure_lecture!(row)
        offering = create_offering!(row, lecture)
        record_applied_result!(row, lecture:, offering:)
      when 'update_offering'
        lecture, offering = update_offering!(row)
        record_applied_result!(row, lecture:, offering:)
      when 'unchanged'
        lecture, offering = touch_last_seen!(row)
        record_applied_result!(row, lecture:, offering:)
      when 'mark_missing'
        lecture, offering = mark_missing!(row)
        record_applied_result!(row, lecture:, offering:)
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
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      concurrent = Lecture.canonical.lock.find_by(normalized_key: row.normalized_key)
      return concurrent if concurrent

      raise
    end

    def ensure_lecture!(row)
      lecture = Lecture.canonical.lock.find_by(id: row.matched_lecture_id)
      raise Error, "照合済みLectureが見つかりません: #{row.matched_lecture_id}" unless lecture
      validate_lecture_identity!(lecture, row)

      lecture
    end

    def create_offering!(row, lecture)
      lecture.lock!
      validate_lecture_identity!(lecture, row)
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

    def validate_lecture_identity!(lecture, row)
      return if lecture.merged_into_lecture_id.nil? && row.normalized_key.present? && lecture.normalized_key == row.normalized_key

      raise Error, "Lectureのnormalized_keyが解析時から変わっています: #{lecture.id}"
    end

    def update_offering!(row)
      lecture = ensure_lecture!(row)
      offering = LectureOffering.lock.find(row.matched_offering_id)
      raise Error, "既存Offeringのlecture_idが解析時から変わっています: #{offering.id}" unless offering.lecture_id == lecture.id
      ensure_snapshot!(offering, row)

      attributes = offering_attributes(row).merge(
        first_seen_import_run_id: offering.first_seen_import_run_id || run.id,
        last_seen_import_run: run,
        missing_since_import_run: nil
      )
      offering.update!(attributes)
      replace_slots!(offering, row.after_values.fetch('slots', []))
      [lecture, offering]
    end

    def touch_last_seen!(row)
      lecture = ensure_lecture!(row)
      offering = LectureOffering.lock.find(row.matched_offering_id)
      raise Error, "既存Offeringのlecture_idが解析時から変わっています: #{offering.id}" unless offering.lecture_id == lecture.id
      ensure_snapshot!(offering, row)

      offering.update_columns(
        last_seen_import_run_id: run.id,
        first_seen_import_run_id: offering.first_seen_import_run_id || run.id,
        source_status: 'active',
        missing_since_import_run_id: nil
      )
      [lecture, offering]
    end

    def mark_missing!(row)
      lecture = ensure_lecture!(row)
      offering = LectureOffering.lock.find(row.matched_offering_id)
      raise Error, "既存Offeringのlecture_idが解析時から変わっています: #{offering.id}" unless offering.lecture_id == lecture.id
      ensure_snapshot!(offering, row)

      offering.update_columns(
        source_status: 'missing',
        missing_since_import_run_id: offering.missing_since_import_run_id || run.id,
        updated_at: operation_time
      )
      [lecture, offering]
    end

    def record_applied_result!(row, lecture:, offering: nil)
      row.update_columns(applied_lecture_id: lecture.id, applied_offering_id: offering&.id)
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
      if @started_application && @original_status == 'applied_without_missing' && current_status == 'applied_without_missing'
        SyllabusImportRun.where(id: run.id, status: 'applied_without_missing').update_all(
          error_summary: error.message,
          finished_at: Time.current
        )
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

  end
end
