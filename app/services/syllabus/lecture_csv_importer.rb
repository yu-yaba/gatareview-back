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
      keyword_init: true
    )

    def initialize(csv_path:)
      @csv_path = csv_path.to_s
    end

    def call
      path = resolve_csv_path
      validate_csv_path!(path)

      lectures_to_import = []
      faculty_counts = Hash.new(0)
      skipped_rows_count = 0
      total_rows_processed = 0
      lecture_count_before = Lecture.count

      begin
        CSV.foreach(path, headers: false, encoding: 'UTF-8') do |row|
          total_rows_processed += 1
          validate_column_count!(row, total_rows_processed)

          title = normalize_text(row[0])
          lecturer = normalize_lecturer(row[1])
          faculty = normalize_text(row[2])

          if title.blank? || lecturer.blank? || faculty.blank?
            skipped_rows_count += 1
            next
          end

          lectures_to_import << Lecture.new(title: title, lecturer: lecturer, faculty: faculty)
          faculty_counts[faculty] += 1
        end
      rescue CSV::MalformedCSVError => e
        raise Error, "CSV の解析に失敗しました: #{e.message}"
      end

      Lecture.import(lectures_to_import, validate: false, ignore: true) if lectures_to_import.any?

      lecture_count_after = Lecture.count
      inserted_count = lecture_count_after - lecture_count_before

      Result.new(
        path: path,
        total_rows_processed: total_rows_processed,
        skipped_rows_count: skipped_rows_count,
        prepared_rows_count: lectures_to_import.size,
        lecture_count_before: lecture_count_before,
        lecture_count_after: lecture_count_after,
        inserted_count: inserted_count,
        ignored_count: lectures_to_import.size - inserted_count,
        faculty_counts: faculty_counts.sort.to_h
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
      return if row.length == 3

      raise Error, "[行 #{row_number}] CSV の列数が不正です。3 列を期待しましたが #{row.length} 列です。"
    end

    def normalize_text(text)
      text.to_s.tr("\u00A0", ' ').gsub(/[[:space:]]+/, ' ').strip
    end

    def normalize_lecturer(text)
      text.to_s.tr("\u00A0", ' ').tr('　', ' ').gsub(/[[:space:]]+/, ' ').strip
    end
  end
end
