# frozen_string_literal: true

FactoryBot.define do
  factory :syllabus_organization do
    sequence(:code) { |n| format('Z%02d', n) }
    sequence(:name) { |n| "テスト所属#{n}" }
    sequence(:faculty_label) { |n| "Z:テスト所属#{n}" }
    enabled_for_import { true }
    valid_from_year { 2026 }
  end

  factory :syllabus_import_run do
    year { 2027 }
    source_type { 'csv_v2' }
    source_file_name { 'lectureData_2027.csv' }
    source_size_bytes { 100 }
    source_sha256 { 'a' * 64 }
    status { 'analyzing' }
    started_at { Time.current }
  end

  factory :lecture_alias do
    association :lecture
    title { lecture.title }
    lecturer { lecture.lecturer }
    faculty { lecture.faculty }
    confirmed { true }
    match_method { 'manual' }
  end
end
