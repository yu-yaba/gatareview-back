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
end
