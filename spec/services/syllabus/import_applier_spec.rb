# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require 'tmpdir'

RSpec.describe Syllabus::ImportApplier do
  around do |example|
    Dir.mktmpdir { |directory| @directory = directory; example.run }
  end

  before do
    SyllabusOrganization.update_all(enabled_for_import: false)
    organization = SyllabusOrganization.find_or_initialize_by(code: '01', valid_from_year: 2026)
    organization.update!(name: '人文学部', faculty_label: 'H:人文学部', enabled_for_import: true)
  end

  def analyzed_run(lecture)
    path = File.join(@directory, 'lectureData_2027.csv')
    CSV.open(path, 'w') do |csv|
      csv << [lecture.title, lecture.lecturer, lecture.faculty, 2027, '271H2001', '01', '第1学期', '第1ターム', '月2|木2']
    end
    Syllabus::ImportAnalyzer.new(csv_path: path).call.run
  end

  it '確認済みrunを適用し、Reviewの参照と集計を変えないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    review = FactoryBot.create(:review, lecture:)
    run = analyzed_run(lecture)
    before_review_data = [Review.count, Review.group(:lecture_id).count, review.reload.lecture_id]

    result = described_class.new(import_run_id: run.id, confirm: true).call
    offering = LectureOffering.find_by!(year: 2027, registration_code: '271H2001')

    expect(result.run.status).to eq('applied')
    expect(offering.lecture).to eq(lecture)
    expect(offering.offering_slots.pluck(:day, :period)).to contain_exactly([1, 2], [4, 2])
    expect([Review.count, Review.group(:lecture_id).count, review.reload.lecture_id]).to eq(before_review_data)
  end

  it '適用したOfferingをrollbackでき、LectureとReviewは削除しないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    review = FactoryBot.create(:review, lecture:)
    run = analyzed_run(lecture)
    described_class.new(import_run_id: run.id, confirm: true).call

    rollback = Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call

    expect(rollback.run.status).to eq('rolled_back')
    expect(Lecture.exists?(lecture.id)).to be(true)
    expect(Review.exists?(review.id)).to be(true)
    expect(LectureOffering.find_by(year: 2027, registration_code: '271H2001')).to be_nil
  end

  it '適用後に作成Offeringを参照するReviewと時間割があればrollbackを拒否すること' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    run = analyzed_run(lecture)
    described_class.new(import_run_id: run.id, confirm: true).call
    offering = LectureOffering.find_by!(year: 2027, registration_code: '271H2001')
    review = FactoryBot.create(
      :review,
      lecture:,
      lecture_offering: offering,
      period_year: 2027,
      period_term: '1ターム'
    )
    timetable_entry = FactoryBot.create(
      :timetable_entry,
      lecture:,
      lecture_offering: offering,
      year: 2027,
      term: 1,
      day: 1,
      period: 2
    )

    expect { Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(Syllabus::ImportRollback::Error, /参照されている/)

    expect(run.reload.status).to eq('applied')
    expect(LectureOffering.exists?(offering.id)).to be(true)
    expect(review.reload.lecture_offering_id).to eq(offering.id)
    expect(timetable_entry.reload.lecture_offering_id).to eq(offering.id)
  end

  it 'CONFIRMなしでは適用しないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    run = analyzed_run(lecture)

    expect { described_class.new(import_run_id: run.id, confirm: false).call }
      .to raise_error(described_class::Error, /CONFIRM/)
    expect(run.reload.status).to eq('analyzed')
    expect(LectureOffering.where(year: 2027)).to be_empty
  end

  it '保留した未掲載Offeringだけを同じrunで後からmissingにできること' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    missing_candidate = LectureOffering.create!(
      lecture: lecture,
      year: 2027,
      registration_code: '271H9999',
      shozoku_code: '01',
      term_code: 'A'
    )
    run = analyzed_run(lecture)

    result = described_class.new(import_run_id: run.id, confirm: true, confirm_missing: false).call

    expect(result.skipped_missing_rows).to eq(1)
    expect(result.run.status).to eq('applied_without_missing')
    expect(missing_candidate.reload.source_status).to eq('active')

    offering_count = LectureOffering.where(year: 2027).count
    completion = described_class.new(import_run_id: run.id, confirm: true, confirm_missing: true).call

    expect(completion.run.status).to eq('applied')
    expect(completion.applied_rows).to eq(1)
    expect(completion.skipped_missing_rows).to eq(0)
    expect(missing_candidate.reload.source_status).to eq('missing')
    expect(LectureOffering.where(year: 2027).count).to eq(offering_count)
  end

  it '未掲載差分を保留したrunも同じCSVの二重適用を拒否すること' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H9999',
      shozoku_code: '01',
      term_code: 'A'
    )
    first_run = analyzed_run(lecture)
    described_class.new(import_run_id: first_run.id, confirm: true, confirm_missing: false).call
    second_run = analyzed_run(lecture)

    expect { described_class.new(import_run_id: second_run.id, confirm: true).call }
      .to raise_error(described_class::Error, /既に適用済み/)
    expect(second_run.reload.status).to eq('analyzed')
  end

  it '未掲載差分を保留したrunのrollbackでは未掲載Offeringを変更しないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    missing_candidate = LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H9999',
      shozoku_code: '01',
      term_code: 'A'
    )
    run = analyzed_run(lecture)
    described_class.new(import_run_id: run.id, confirm: true, confirm_missing: false).call

    rollback = Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call

    expect(rollback.run.status).to eq('rolled_back')
    expect(missing_candidate.reload.source_status).to eq('active')
    expect(LectureOffering.find_by(year: 2027, registration_code: '271H2001')).to be_nil
  end

  it '同じ年度・同じCSVの二重適用を拒否すること' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    first_run = analyzed_run(lecture)
    described_class.new(import_run_id: first_run.id, confirm: true).call
    second_run = analyzed_run(lecture)

    expect { described_class.new(import_run_id: second_run.id, confirm: true).call }
      .to raise_error(described_class::Error, /既に適用済み/)
    expect(second_run.reload.status).to eq('analyzed')
  end
end
