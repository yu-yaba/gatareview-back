# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require 'tmpdir'

RSpec.describe Syllabus::ImportAnalyzer do
  around do |example|
    Dir.mktmpdir { |directory| @directory = directory; example.run }
  end

  before do
    SyllabusOrganization.update_all(enabled_for_import: false)
    organization = SyllabusOrganization.find_or_initialize_by(code: '01', valid_from_year: 2026)
    organization.update!(name: '人文学部', faculty_label: 'H:人文学部', enabled_for_import: true)
  end

  def write_csv(name, rows)
    path = File.join(@directory, name)
    CSV.open(path, 'w') { |csv| rows.each { |row| csv << row } }
    path
  end

  def v2_row(year: 2027, code: '271H2001', title: '心理学概論Ａ', lecturer: '山田 太郎', term: '第1ターム', schedule: '月2')
    [title, lecturer, 'H:人文学部', year, code, '01', '第1学期', term, schedule]
  end

  it '年度が違っても同じ講義名・教員・所属を既存Lectureへ照合し、解析時はDBを変更しないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論A', lecturer: '山田太郎', faculty: 'H:人文学部')
    LectureOffering.create!(lecture:, year: 2026, registration_code: '261H2001', shozoku_code: '01', term_code: 'A')
    path = write_csv('lectureData_2027.csv', [v2_row])

    expect { described_class.new(csv_path: path).call }.not_to change(LectureOffering, :count)
    run = SyllabusImportRun.order(:id).last
    row = run.syllabus_import_rows.find_by!(source_row_number: 1)

    expect(run).to have_attributes(status: 'analyzed', new_lectures_count: 0, new_offerings_count: 1, error_count: 0, conflict_count: 0)
    expect(row).to have_attributes(action: 'create_offering', matched_lecture_id: lecture.id)
  end

  it '未知の曜日表現を集中扱いせずerrorにすること' do
    path = write_csv('unknown.csv', [v2_row(schedule: '曜日未定')])

    run = described_class.new(csv_path: path).call.run
    row = run.syllabus_import_rows.find_by!(source_row_number: 1)

    expect(run.error_count).to eq(1)
    expect(row).to have_attributes(action: 'error', schedule_kind: 'unknown')
  end

  it '不正なUTF-8のCSVを拒否すること' do
    path = File.join(@directory, 'invalid.csv')
    File.binwrite(path, "\xFF,teacher,H:faculty\n")

    expect { described_class.new(csv_path: path).call }
      .to raise_error(described_class::Error, /UTF-8/)
  end

  it '同年度CSVから消えたOfferingを削除せずmissing差分として保存すること' do
    lecture = FactoryBot.create(:lecture, title: '既存講義', lecturer: '既存 教員', faculty: 'H:人文学部')
    offering = LectureOffering.create!(lecture:, year: 2027, registration_code: '271H9999', shozoku_code: '01', term_code: 'A')
    path = write_csv('missing.csv', [v2_row])

    run = described_class.new(csv_path: path).call.run
    missing = run.syllabus_import_rows.find_by!(action: 'mark_missing')

    expect(missing).to have_attributes(source_row_number: nil, matched_offering_id: offering.id)
    expect(offering.reload.source_status).to eq('active')
  end

  it '初回runでも既存active Offeringをbaselineにして大幅減少を拒否すること' do
    5.times do |index|
      lecture = FactoryBot.create(
        :lecture,
        title: "既存講義#{index}",
        lecturer: "既存教員#{index}",
        faculty: 'H:人文学部'
      )
      LectureOffering.create!(
        lecture:,
        year: 2027,
        registration_code: format('271H9%03d', index),
        shozoku_code: '01',
        term_code: 'A'
      )
    end
    path = write_csv('too-small-first-run.csv', [v2_row])

    run = described_class.new(csv_path: path).call.run

    expect(run.error_count).to eq(1)
    expect(run.error_summary).to match(/既存DB baselineから20%以上減少/)
    expect(run.syllabus_import_rows.where(action: 'mark_missing').count).to eq(5)
    expect { Syllabus::ImportApplier.new(import_run_id: run.id, confirm: true, confirm_missing: true).call }
      .to raise_error(Syllabus::ImportApplier::Error, /適用できないrun/)
  end

  it '類似する既存Lectureがある場合は自動作成せずconflictにすること' do
    FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '別の教員', faculty: 'H:人文学部')
    path = write_csv('conflict.csv', [v2_row])

    run = described_class.new(csv_path: path).call.run

    expect(run).to have_attributes(new_lectures_count: 0, conflict_count: 1)
    expect(run.syllabus_import_rows.find_by!(source_row_number: 1).action).to eq('conflict')
  end
end
