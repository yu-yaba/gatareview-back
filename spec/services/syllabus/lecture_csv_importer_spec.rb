# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Syllabus::LectureCsvImporter do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmp_dir = Pathname(dir)
      example.run
    end
  end

  def write_csv(filename, content)
    path = @tmp_dir.join(filename)
    path.write(content)
    path
  end

  it 'imports lectures from an explicitly specified CSV and reports counts' do
    create(:lecture, title: '既存講義', lecturer: '既存 教員', faculty: 'H:人文学部')
    csv_path = write_csv(
      'lectureData_2026.csv',
      <<~CSV
        新講義A,山田　太郎,E:経済科学部
        新講義B,佐藤 花子,E:経済科学部
        既存講義,既存 教員,H:人文学部
      CSV
    )

    result = described_class.new(csv_path: csv_path).call

    expect(result.path).to eq(csv_path)
    expect(result.total_rows_processed).to eq(3)
    expect(result.skipped_rows_count).to eq(0)
    expect(result.prepared_rows_count).to eq(3)
    expect(result.lecture_count_before).to eq(1)
    expect(result.lecture_count_after).to eq(3)
    expect(result.inserted_count).to eq(2)
    expect(result.ignored_count).to eq(1)
    expect(result.faculty_counts).to eq(
      'E:経済科学部' => 2,
      'H:人文学部' => 1
    )
    expect(Lecture.find_by(title: '新講義A')&.lecturer).to eq('山田 太郎')
  end

  it 'skips rows with blank required fields' do
    csv_path = write_csv(
      'lectureData_2026.csv',
      <<~CSV
        新講義A,山田 太郎,E:経済科学部
        ,佐藤 花子,E:経済科学部
      CSV
    )

    result = described_class.new(csv_path: csv_path).call

    expect(result.total_rows_processed).to eq(2)
    expect(result.skipped_rows_count).to eq(1)
    expect(result.inserted_count).to eq(1)
    expect(Lecture.where(title: '新講義A').count).to eq(1)
  end

  it 'fails when CSV_PATH is missing' do
    expect { described_class.new(csv_path: nil).call }
      .to raise_error(ArgumentError, /CSV_PATH is required/)
  end

  it 'fails when a row does not have exactly three columns' do
    csv_path = write_csv('lectureData_2026.csv', "新講義A,山田 太郎,E:経済科学部,余分な列\n")

    expect { described_class.new(csv_path: csv_path).call }
      .to raise_error(described_class::Error, /列数が不正/)
  end

  it 'imports v2 offerings, matches an existing lecture, and expands full-width day periods' do
    lecture = create(:lecture, title: '既存講義', lecturer: '既存 教員', faculty: 'H:人文学部')
    csv_path = write_csv(
      'lectureData_2026.csv',
      "既存講義,既存 教員,H:人文学部,2026,261H2001,01,第1学期,\"第1,2ターム\",月２|木 2\n"
    )

    result = described_class.new(csv_path: csv_path).call
    offering = LectureOffering.find_by!(year: 2026, registration_code: '261H2001')

    expect(result.offering_count).to eq(1)
    expect(result.slot_count).to eq(2)
    expect(result.matched_existing_lecture_count).to eq(1)
    expect(offering.lecture).to eq(lecture)
    expect(offering).to have_attributes(shozoku_code: '01', semester_label: '第1学期', term_label: '第1,2ターム', term_code: 'E')
    expect(offering.offering_slots.pluck(:day, :period)).to contain_exactly([1, 2], [4, 2])
  end

  it 'upserts offerings and replaces their slots when the same v2 CSV is imported again' do
    first_path = write_csv(
      'first.csv',
      "新講義,山田 太郎,H:人文学部,2026,261H2001,01,第1学期,第1ターム,月2|木2\n"
    )
    described_class.new(csv_path: first_path).call
    offering = LectureOffering.find_by!(year: 2026, registration_code: '261H2001')

    updated_path = write_csv(
      'updated.csv',
      "新講義,山田 太郎,H:人文学部,2026,261H2001,01,第2学期,第2ターム,火3\n"
    )
    result = described_class.new(csv_path: updated_path).call

    expect(LectureOffering.find_by!(year: 2026, registration_code: '261H2001')).to have_attributes(id: offering.id, term_code: 'B', semester_label: '第2学期')
    expect(offering.reload.offering_slots.pluck(:day, :period)).to eq([[2, 3]])
    expect(result.inserted_count).to eq(0)
    expect(result.matched_existing_lecture_count).to eq(1)
  end

  it 'keeps the legacy three-column import compatible without creating offerings' do
    csv_path = write_csv('legacy.csv', "旧形式講義,田中 太郎,H:人文学部\n")

    result = described_class.new(csv_path: csv_path).call

    expect(result.offering_count).to eq(0)
    expect(result.slot_count).to eq(0)
    expect(Lecture.find_by!(title: '旧形式講義').lecture_offerings).to be_empty
  end
end
