# frozen_string_literal: true

require 'csv'
require 'pathname'
require 'activerecord-import'

module Syllabus
  class LectureCsvImporter
    Error = Class.new(StandardError)

    Result = Struct.new(
      :path,
      :total_rows_processed,
      :skipped_rows_count,
      :prepared_rows_count,
      :lecture_count_before,
      :lecture_count_after,
      :inserted_count,
      :ignored_count,
      :faculty_counts,
      :offering_count,
      :slot_count,
      :matched_existing_lecture_count,
      keyword_init: true
    )

    def initialize(csv_path:)
      @csv_path = csv_path.to_s
    end

    def call
      path = resolve_csv_path
      validate_csv_path!(path)

      lectures_to_import = []
      offering_rows = []
      faculty_counts = Hash.new(0)
      skipped_rows_count = 0
      total_rows_processed = 0
      lecture_count_before = Lecture.count
      matched_existing_lecture_count = 0

      begin
        CSV.foreach(path, headers: false, encoding: 'UTF-8') do |row|
          total_rows_processed += 1
          format = validate_column_count!(row, total_rows_processed)

          title = normalize_text(row[0])
          lecturer = normalize_lecturer(row[1])
          faculty = normalize_text(row[2])

          if title.blank? || lecturer.blank? || faculty.blank?
            skipped_rows_count += 1
            next
          end

          year = normalize_year(row[3]) if format == :v2
          registration_code = normalize_text(row[4]) if format == :v2
          shozoku_code = normalize_text(row[5]) if format == :v2
          if format == :v2 && (year.nil? || registration_code.blank? || shozoku_code.blank?)
            skipped_rows_count += 1
            next
          end

          lecture = Lecture.find_or_initialize_by(title: title, lecturer: lecturer, faculty: faculty)
          if lecture.persisted?
            matched_existing_lecture_count += 1
          else
            lecture.save!
          end

          lectures_to_import << lecture
          faculty_counts[faculty] += 1

          next if format == :legacy

          offering_rows << {
            lecture_id: lecture.id,
            year: year,
            registration_code: registration_code,
            shozoku_code: shozoku_code,
            semester_label: normalize_text(row[6]).presence,
            term_label: normalize_text(row[7]).presence,
            term_code: LectureOffering.term_code_for(row[7]),
            day_periods: row[8]
          }
        end
      rescue CSV::MalformedCSVError => e
        raise Error, "CSV の解析に失敗しました: #{e.message}"
      end

      lecture_count_after = Lecture.count
      inserted_count = lecture_count_after - lecture_count_before
      import_offerings_and_slots(offering_rows)

      Result.new(
        path: path,
        total_rows_processed: total_rows_processed,
        skipped_rows_count: skipped_rows_count,
        prepared_rows_count: total_rows_processed - skipped_rows_count,
        lecture_count_before: lecture_count_before,
        lecture_count_after: lecture_count_after,
        inserted_count: inserted_count,
        ignored_count: lectures_to_import.size - inserted_count,
        faculty_counts: faculty_counts.sort.to_h,
        offering_count: offering_rows.size,
        slot_count: offering_rows.sum { |row| parse_day_periods(row[:day_periods]).size },
        matched_existing_lecture_count: matched_existing_lecture_count
      )
    end

    private

    attr_reader :csv_path

    def resolve_csv_path
      path = Pathname.new(csv_path)
      path.absolute? ? path : Rails.root.join(path)
    end

    def validate_csv_path!(path)
      raise ArgumentError, 'CSV_PATH is required. Example: CSV_PATH=lectureData_2026.csv' if csv_path.blank?
      raise Error, "CSV ファイルが見つかりません: #{path}" unless path.exist?
      raise Error, "CSV ファイルではありません: #{path}" unless path.extname.downcase == '.csv'
    end

    def validate_column_count!(row, row_number)
      return :legacy if row.length == 3
      return :v2 if row.length == 9

      raise Error, "[行 #{row_number}] CSV の列数が不正です。3 または 9 列を期待しましたが #{row.length} 列です。"
    end

    def normalize_text(text)
      text.to_s.tr("\u00A0", ' ').gsub(/[[:space:]]+/, ' ').strip
    end

    def normalize_lecturer(text)
      text.to_s.tr("\u00A0", ' ').tr('　', ' ').gsub(/[[:space:]]+/, ' ').strip
    end

    def normalize_year(value)
      year = Integer(normalize_text(value), 10)
      year if year.between?(1000, 9999)
    rescue ArgumentError
      nil
    end

    def import_offerings_and_slots(rows)
      return if rows.empty?

      offerings = rows.map do |row|
        LectureOffering.new(row.except(:day_periods))
      end
      LectureOffering.import(
        offerings,
        validate: false,
        on_duplicate_key_update: %i[lecture_id shozoku_code semester_label term_label term_code updated_at]
      )

      offerings_by_key = LectureOffering.where(year: rows.map { |row| row[:year] }.uniq)
                                        .where(registration_code: rows.map { |row| row[:registration_code] }.uniq)
                                        .index_by { |offering| [offering.year, offering.registration_code] }
      imported_offering_ids = offerings_by_key.values_at(*rows.map { |row| [row[:year], row[:registration_code]] }.uniq).compact.map(&:id)
      OfferingSlot.where(lecture_offering_id: imported_offering_ids).delete_all

      slots = rows.flat_map do |row|
        offering = offerings_by_key.fetch([row[:year], row[:registration_code]])
        parse_day_periods(row[:day_periods]).map do |day, period|
          OfferingSlot.new(lecture_offering_id: offering.id, day: day, period: period)
        end
      end
      OfferingSlot.import(slots, validate: false, ignore: true) if slots.any?
    end

    def parse_day_periods(value)
      normalize_text(value).tr('０１２３４５６７', '01234567')
                           .scan(/([月火水木金土日])\s*([1-7])/)
                           .map { |day, period| [OfferingSlot::DAYS.fetch(day), period.to_i] }
    end
  end
end
