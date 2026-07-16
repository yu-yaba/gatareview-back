# frozen_string_literal: true

require 'csv'
require 'digest'
require 'pathname'
require 'set'

module Syllabus
  class ImportAnalyzer
    Error = Class.new(StandardError)
    DROP_THRESHOLD = 0.20

    Result = Struct.new(:run, keyword_init: true)

    def initialize(csv_path:, year: nil, now: Time.current)
      @csv_path = csv_path.to_s
      @requested_year = year
      @now = now
    end

    def call
      path = resolve_path
      validate_path!(path)
      source_bytes = path.binread
      rows = parse_csv(source_bytes)
      format = detect_format!(rows)
      year = determine_year!(rows, format)

      run = SyllabusImportRun.create!(
        year:,
        source_type: format == :v2 ? 'csv_v2' : 'legacy_csv',
        source_file_name: path.basename.to_s,
        source_size_bytes: source_bytes.bytesize,
        source_sha256: Digest::SHA256.hexdigest(source_bytes),
        status: 'analyzing',
        started_at: @now
      )

      analyze!(run, rows, format)
      Result.new(run: run.reload)
    rescue CSV::MalformedCSVError => e
      raise Error, "CSVの解析に失敗しました: #{e.message}"
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
      run&.update_columns(status: 'failed', error_summary: e.message, finished_at: Time.current)
      raise Error, e.message
    rescue Error => e
      run&.update_columns(status: 'failed', error_summary: e.message, finished_at: Time.current)
      raise
    end

    private

    attr_reader :csv_path, :requested_year, :now

    def resolve_path
      path = Pathname.new(csv_path)
      path.absolute? ? path : Rails.root.join(path)
    end

    def validate_path!(path)
      raise ArgumentError, 'CSV_PATH is required' if csv_path.blank?
      raise Error, "CSVファイルが見つかりません: #{path}" unless path.exist?
      raise Error, "CSVファイルではありません: #{path}" unless path.extname.downcase == '.csv'
    end

    def parse_csv(source_bytes)
      utf8_source = source_bytes.dup.force_encoding(Encoding::UTF_8)
      raise Error, 'CSVがUTF-8として不正です' unless utf8_source.valid_encoding?

      CSV.parse(utf8_source, headers: false)
    end

    def detect_format!(rows)
      raise Error, 'CSVが空です' if rows.empty?

      lengths = rows.map(&:length).uniq
      return :legacy if lengths == [3]
      return :v2 if lengths == [9]

      raise Error, "CSVの列数が統一されていません: #{lengths.sort.join(', ')}列"
    end

    def determine_year!(rows, format)
      if format == :legacy
        year = integer_year(requested_year.presence || Time.zone.today.year)
        raise Error, '3列CSVではYEARに4桁年度を指定してください' unless year

        return year
      end

      years = rows.filter_map { |row| integer_year(row[3]) }.uniq
      raise Error, 'CSV内の年度が不正または複数です' unless years.one? && rows.all? { |row| integer_year(row[3]) == years.first }
      raise Error, "YEARとCSV内年度が一致しません: #{requested_year} / #{years.first}" if requested_year.present? && integer_year(requested_year) != years.first

      years.first
    end

    def integer_year(value)
      year = Integer(Normalizer.text(value), 10)
      year if year.between?(2000, 2100)
    rescue ArgumentError, TypeError
      nil
    end

    def analyze!(run, csv_rows, format)
      context = build_context(run.year)
      plans = csv_rows.each_with_index.map do |row, index|
        format == :v2 ? analyze_v2_row(row, index + 1, context) : analyze_legacy_row(row, index + 1, context)
      end
      mark_duplicate_registration_codes!(plans) if format == :v2
      append_missing_plans!(plans, context) if format == :v2

      completeness_errors = format == :v2 ? completeness_errors(plans, context, run.year) : []
      persist_plans!(run, plans)
      finalize_run!(run, plans, completeness_errors)
    end

    def build_context(year)
      lectures = Lecture.canonical.to_a
      lecture_keys = Hash.new { |hash, key| hash[key] = [] }
      title_faculty = Hash.new { |hash, key| hash[key] = [] }
      lecturer_faculty = Hash.new { |hash, key| hash[key] = [] }

      lectures.each do |lecture|
        key = lecture.normalized_key.presence || Normalizer.lecture_key(title: lecture.title, lecturer: lecture.lecturer, faculty: lecture.faculty)
        lecture_keys[key] << lecture
        title_faculty[[Normalizer.title(lecture.title), Normalizer.faculty(lecture.faculty)]] << lecture
        lecturer_faculty[[Normalizer.lecturer(lecture.lecturer), Normalizer.faculty(lecture.faculty)]] << lecture
      end

      {
        lecture_keys:,
        title_faculty:,
        lecturer_faculty:,
        aliases: LectureAlias.confirmed.includes(:lecture).index_by(&:normalized_key),
        offerings: LectureOffering.where(year:).includes(:offering_slots, :lecture).index_by(&:registration_code),
        organizations: SyllabusOrganization.enabled.for_year(year).index_by(&:code),
        seen_registration_codes: []
      }
    end

    def analyze_v2_row(row, row_number, context)
      source = normalized_v2_source(row)
      messages = []
      messages << '必須項目が不足しています' if %i[title lecturer faculty registration_code shozoku_code].any? { |key| source[key].blank? }

      organization = context[:organizations][source[:shozoku_code]]
      messages << "未知または対象外の所属コードです: #{source[:shozoku_code]}" unless organization
      if organization && Normalizer.faculty(organization.faculty_label) != Normalizer.faculty(source[:faculty])
        messages << "所属コードとfacultyが一致しません: #{organization.faculty_label} / #{source[:faculty]}"
      end

      source[:term_code] = LectureOffering.term_code_for(source[:term_label])
      messages << "未知の開講区分です: #{source[:term_label]}" if source[:term_code].blank?

      schedule = ScheduleParser.call(source[:raw_day_periods], term_code: source[:term_code])
      source[:schedule_kind] = schedule.kind
      source[:slots] = schedule.slots
      messages << schedule.error if schedule.error

      key = Normalizer.lecture_key(title: source[:title], lecturer: source[:lecturer], faculty: source[:faculty])
      source[:normalized_key] = key
      checksum = Normalizer.checksum(source.except(:normalized_key))
      source[:source_checksum] = checksum

      return error_plan(row_number, source, messages) if messages.any?

      existing_offering = context[:offerings][source[:registration_code]]
      match = find_lecture_match(source, key, context)
      plan_for_match(row_number, source, existing_offering, match, context)
    end

    def normalized_v2_source(row)
      {
        title: Normalizer.text(row[0]),
        lecturer: Normalizer.text(row[1]),
        faculty: Normalizer.text(row[2]),
        year: integer_year(row[3]),
        registration_code: Normalizer.text(row[4]),
        shozoku_code: Normalizer.text(row[5]).upcase,
        semester_label: Normalizer.text(row[6]).presence,
        term_label: Normalizer.text(row[7]).presence,
        raw_day_periods: Normalizer.text(row[8])
      }
    end

    def analyze_legacy_row(row, row_number, context)
      source = {
        title: Normalizer.text(row[0]),
        lecturer: Normalizer.text(row[1]),
        faculty: Normalizer.text(row[2])
      }
      messages = []
      messages << '必須項目が不足しています' if source.values.any?(&:blank?)
      key = Normalizer.lecture_key(title: source[:title], lecturer: source[:lecturer], faculty: source[:faculty])
      source[:normalized_key] = key
      return error_plan(row_number, source, messages) if messages.any?

      match = find_lecture_match(source, key, context)
      if match[:conflict]
        build_plan(row_number:, source:, action: 'conflict', messages: match[:messages])
      elsif match[:lecture]
        build_plan(row_number:, source:, action: 'lecture_unchanged', matched_lecture: match[:lecture])
      else
        build_plan(row_number:, source:, action: 'create_lecture')
      end
    end

    def find_lecture_match(source, key, context)
      alias_record = context[:aliases][key]
      exact = context[:lecture_keys][key]
      candidates = ([alias_record&.lecture] + exact).compact.uniq

      return { conflict: true, messages: ['aliasと完全一致Lectureの参照先が競合しています'] } if candidates.many?
      return { lecture: candidates.first } if candidates.one?

      similar = context[:title_faculty][[Normalizer.title(source[:title]), Normalizer.faculty(source[:faculty])]] |
                context[:lecturer_faculty][[Normalizer.lecturer(source[:lecturer]), Normalizer.faculty(source[:faculty])]]
      return { conflict: true, messages: ["類似する既存Lectureがあります: #{similar.map(&:id).join(', ')}"] } if similar.any?

      { lecture: nil }
    end

    def plan_for_match(row_number, source, existing_offering, match, context)
      if match[:conflict]
        return build_plan(row_number:, source:, action: 'conflict', messages: match[:messages], matched_offering: existing_offering)
      end

      if existing_offering
        matched_lecture = match[:lecture]
        if matched_lecture.nil? || existing_offering.lecture_id != matched_lecture.id
          return build_plan(
            row_number:,
            source:,
            action: 'conflict',
            messages: ["既存Offeringのlecture_idを変更する必要があります: #{existing_offering.lecture_id} → #{matched_lecture&.id || '新規'}"],
            matched_lecture:,
            matched_offering: existing_offering,
            before_values: offering_snapshot(existing_offering)
          )
        end

        after_values = offering_attributes(source, context)
        before_values = offering_snapshot(existing_offering)
        action = offering_changed?(existing_offering, after_values) ? 'update_offering' : 'unchanged'
        return build_plan(row_number:, source:, action:, matched_lecture:, matched_offering: existing_offering, before_values:, after_values:)
      end

      action = match[:lecture] ? 'create_offering' : 'create_lecture_and_offering'
      build_plan(row_number:, source:, action:, matched_lecture: match[:lecture], after_values: offering_attributes(source, context))
    end

    def offering_attributes(source, context)
      organization = context[:organizations][source[:shozoku_code]]
      {
        'year' => source[:year],
        'registration_code' => source[:registration_code],
        'shozoku_code' => source[:shozoku_code],
        'syllabus_organization_id' => organization&.id,
        'semester_label' => source[:semester_label],
        'term_label' => source[:term_label],
        'term_code' => source[:term_code],
        'source_title' => source[:title],
        'source_lecturer' => source[:lecturer],
        'source_faculty' => source[:faculty],
        'raw_day_periods' => source[:raw_day_periods],
        'schedule_kind' => source[:schedule_kind],
        'source_status' => 'active',
        'source_checksum' => source[:source_checksum],
        'slots' => source[:slots].map { |day, period| { 'day' => day, 'period' => period } }
      }
    end

    def offering_snapshot(offering)
      {
        'lecture_id' => offering.lecture_id,
        'year' => offering.year,
        'registration_code' => offering.registration_code,
        'shozoku_code' => offering.shozoku_code,
        'syllabus_organization_id' => offering.syllabus_organization_id,
        'semester_label' => offering.semester_label,
        'term_label' => offering.term_label,
        'term_code' => offering.term_code,
        'source_title' => offering.source_title,
        'source_lecturer' => offering.source_lecturer,
        'source_faculty' => offering.source_faculty,
        'raw_day_periods' => offering.raw_day_periods,
        'schedule_kind' => offering.schedule_kind,
        'source_status' => offering.source_status,
        'source_checksum' => offering.source_checksum,
        'first_seen_import_run_id' => offering.first_seen_import_run_id,
        'last_seen_import_run_id' => offering.last_seen_import_run_id,
        'missing_since_import_run_id' => offering.missing_since_import_run_id,
        'slots' => offering.offering_slots.sort_by { |slot| [slot.day, slot.period] }.map { |slot| { 'day' => slot.day, 'period' => slot.period } }
      }
    end

    def offering_changed?(offering, after_values)
      offering.source_status != 'active' || offering.source_checksum != after_values['source_checksum'] ||
        offering.offering_slots.sort_by { |slot| [slot.day, slot.period] }.map { |slot| [slot.day, slot.period] } !=
          after_values['slots'].map { |slot| [slot['day'], slot['period']] }
    end

    def error_plan(row_number, source, messages)
      build_plan(row_number:, source:, action: 'error', messages:)
    end

    def build_plan(row_number:, source:, action:, messages: [], matched_lecture: nil, matched_offering: nil, before_values: nil, after_values: nil)
      {
        source_row_number: row_number,
        source:,
        action:,
        messages:,
        matched_lecture:,
        matched_offering:,
        before_values:,
        after_values:,
        row_checksum: Normalizer.checksum(source)
      }
    end

    def mark_duplicate_registration_codes!(plans)
      plans.group_by { |plan| [plan.dig(:source, :year), plan.dig(:source, :registration_code)] }.each_value do |duplicates|
        next if duplicates.one? || duplicates.first.dig(:source, :registration_code).blank?

        duplicates.each do |plan|
          plan[:action] = 'conflict'
          plan[:messages] << 'CSV内で同年度・同一開講番号が重複しています'
        end
      end
    end

    def append_missing_plans!(plans, context)
      seen = plans.filter_map { |plan| plan.dig(:source, :registration_code).presence }.to_set
      context[:offerings].each_value do |offering|
        next if seen.include?(offering.registration_code)

        source = {
          year: offering.year,
          registration_code: offering.registration_code,
          title: offering.source_title.presence || offering.lecture.title,
          lecturer: offering.source_lecturer.presence || offering.lecture.lecturer,
          faculty: offering.source_faculty.presence || offering.lecture.faculty,
          normalized_key: offering.lecture.normalized_key
        }
        after_values = offering_snapshot(offering).merge(
          'source_status' => 'missing',
          'missing_since_import_run_id' => nil
        )
        plans << build_plan(
          row_number: nil,
          source:,
          action: 'mark_missing',
          matched_lecture: offering.lecture,
          matched_offering: offering,
          before_values: offering_snapshot(offering),
          after_values:
        )
      end
    end

    def completeness_errors(plans, context, year)
      errors = []
      present_codes = plans.filter_map { |plan| plan.dig(:source, :shozoku_code) }.uniq
      missing_codes = context[:organizations].keys - present_codes
      errors << "対象所属がCSVにありません: #{missing_codes.join(', ')}" if missing_codes.any?

      current_counts = plans.reject { |plan| plan[:action] == 'mark_missing' }
                            .group_by { |plan| plan.dig(:source, :faculty) }
                            .transform_values(&:size)
      previous_run = SyllabusImportRun.applied_to_domain.where(year:).order(applied_at: :desc).first
      previous_counts = previous_run&.faculty_counts || {}
      previous_counts.each do |faculty, previous_count|
        current_count = current_counts[faculty].to_i
        next if previous_count.to_i.zero?
        next if current_count >= previous_count.to_i * (1 - DROP_THRESHOLD)

        errors << "#{faculty}の件数が前回から20%以上減少しています: #{previous_count} → #{current_count}"
      end
      errors
    end

    def persist_plans!(run, plans)
      timestamp = Time.current
      rows = plans.each_with_index.map do |plan, index|
        source = plan[:source]
        {
          syllabus_import_run_id: run.id,
          sequence_number: index + 1,
          source_row_number: plan[:source_row_number],
          year: source[:year] || run.year,
          registration_code: source[:registration_code],
          source_title: source[:title],
          source_lecturer: source[:lecturer],
          source_faculty: source[:faculty],
          normalized_key: source[:normalized_key],
          shozoku_code: source[:shozoku_code],
          semester_label: source[:semester_label],
          term_label: source[:term_label],
          term_code: source[:term_code],
          raw_day_periods: source[:raw_day_periods],
          schedule_kind: source[:schedule_kind],
          action: plan[:action],
          matched_lecture_id: plan[:matched_lecture]&.id,
          matched_offering_id: plan[:matched_offering]&.id,
          messages: plan[:messages],
          before_values: plan[:before_values],
          after_values: plan[:after_values],
          row_checksum: plan[:row_checksum],
          created_at: timestamp,
          updated_at: timestamp
        }
      end

      SyllabusImportRow.insert_all!(rows)
    end

    def finalize_run!(run, plans, completeness_errors)
      faculty_counts = plans.reject { |plan| plan[:action] == 'mark_missing' }
                            .group_by { |plan| plan.dig(:source, :faculty) }
                            .transform_values(&:size)
      error_count = plans.count { |plan| plan[:action] == 'error' } + completeness_errors.size
      conflict_count = plans.count { |plan| plan[:action] == 'conflict' }

      run.update!(
        status: 'analyzed',
        total_rows: plans.count { |plan| plan[:source_row_number].present? },
        valid_rows: plans.count { |plan| !%w[error conflict mark_missing].include?(plan[:action]) },
        new_lectures_count: plans.count { |plan| %w[create_lecture create_lecture_and_offering].include?(plan[:action]) },
        new_offerings_count: plans.count { |plan| %w[create_offering create_lecture_and_offering].include?(plan[:action]) },
        updated_offerings_count: plans.count { |plan| plan[:action] == 'update_offering' },
        unchanged_offerings_count: plans.count { |plan| %w[unchanged lecture_unchanged].include?(plan[:action]) },
        missing_offerings_count: plans.count { |plan| plan[:action] == 'mark_missing' },
        conflict_count:,
        warning_count: 0,
        error_count:,
        faculty_counts:,
        error_summary: completeness_errors.presence&.join("\n"),
        staged_sha256: run.calculated_staged_sha256,
        analyzed_at: Time.current,
        finished_at: Time.current
      )
    end
  end
end
