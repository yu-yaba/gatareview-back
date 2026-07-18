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

  def analyzed_run(lecture, file_name: 'lectureData_2027.csv', term_label: '第1ターム', raw_day_periods: '月2|木2')
    path = File.join(@directory, file_name)
    CSV.open(path, 'w') do |csv|
      csv << [lecture.title, lecture.lecturer, lecture.faculty, 2027, '271H2001', '01', '第1学期', term_label, raw_day_periods]
    end
    Syllabus::ImportAnalyzer.new(csv_path: path).call.run
  end

  def analyzed_legacy_run(title:, file_name:)
    path = File.join(@directory, file_name)
    CSV.open(path, 'w') { |csv| csv << [title, '山田 太郎', 'H:人文学部'] }
    Syllabus::ImportAnalyzer.new(csv_path: path, year: 2027).call.run
  end

  def analyzed_v2_rows(rows, file_name: 'multiple_2027.csv')
    path = File.join(@directory, file_name)
    CSV.open(path, 'w') { |csv| rows.each { |row| csv << row } }
    Syllabus::ImportAnalyzer.new(csv_path: path).call.run
  end

  def v2_row(lecture, code:, term_label: '第1ターム', raw_day_periods: '月2')
    [
      lecture.title, lecture.lecturer, lecture.faculty, 2027, code, '01',
      '第1学期', term_label, raw_day_periods
    ]
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
    run = analyzed_run(lecture, raw_day_periods: '木2|月2')
    described_class.new(import_run_id: run.id, confirm: true).call
    row = run.syllabus_import_rows.find_by!(source_row_number: 1)
    applied_offering_id = row.applied_offering_id

    rollback = Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call

    expect(rollback.run.status).to eq('rolled_back')
    expect(Lecture.exists?(lecture.id)).to be(true)
    expect(Review.exists?(review.id)).to be(true)
    expect(LectureOffering.find_by(year: 2027, registration_code: '271H2001')).to be_nil
    expect(row.reload.applied_offering_id).to eq(applied_offering_id)
    expect(run.reload.calculated_applied_result_sha256).to eq(run.applied_result_sha256)
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
      user: User.create!(
        email: "rollback-#{run.id}@example.com",
        name: 'ロールバック確認ユーザー',
        provider: 'google',
        provider_id: "rollback-#{run.id}"
      ),
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

  it '同じOfferingの2つの解析結果を逆順に適用しても後から古いsnapshotで上書きしないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    offering = LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H2001',
      shozoku_code: '01',
      term_code: 'A'
    )
    older_run = analyzed_run(
      lecture,
      file_name: 'older_2027.csv',
      term_label: '第1ターム',
      raw_day_periods: '月2'
    )
    newer_run = analyzed_run(
      lecture,
      file_name: 'newer_2027.csv',
      term_label: '第2ターム',
      raw_day_periods: '火3'
    )

    described_class.new(import_run_id: newer_run.id, confirm: true).call

    expect { described_class.new(import_run_id: older_run.id, confirm: true).call }
      .to raise_error(described_class::Error, /再解析が必要/)

    expect(older_run.reload.status).to eq('failed')
    expect(offering.reload.term_code).to eq('B')
    expect(offering.offering_slots.pluck(:day, :period)).to eq([[2, 3]])
  end

  it '適用実行が逆順になってもapplied_atを年度ロック内の実際の適用順にすること' do
    delayed_run = analyzed_legacy_run(title: '遅延した講義', file_name: 'delayed.csv')
    first_run = analyzed_legacy_run(title: '先に適用する講義', file_name: 'first.csv')
    delayed_applier = described_class.new(
      import_run_id: delayed_run.id,
      confirm: true,
      now: Time.zone.parse('2026-01-01 00:00:00')
    )

    described_class.new(
      import_run_id: first_run.id,
      confirm: true,
      now: Time.zone.parse('2026-02-01 00:00:00')
    ).call
    delayed_applier.call

    expect(delayed_run.reload.applied_at).to be > first_run.reload.applied_at
  end

  it '未掲載差分の追加適用に失敗しても再試行可能なstatusと失敗理由を保存すること' do
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
    run.update_columns(finished_at: 1.day.ago, error_summary: nil)
    previous_finished_at = run.reload.finished_at
    missing_candidate.update_columns(term_label: '解析後の外部変更')

    expect do
      described_class.new(import_run_id: run.id, confirm: true, confirm_missing: true).call
    end.to raise_error(described_class::Error, /再解析が必要/)

    expect(run.reload.status).to eq('applied_without_missing')
    expect(run.error_summary).to match(/再解析が必要/)
    expect(run.finished_at).to be > previous_finished_at
    expect(missing_candidate.reload.source_status).to eq('active')

    missing_candidate.update_columns(term_label: nil)
    retry_result = described_class.new(
      import_run_id: run.id,
      confirm: true,
      confirm_missing: true
    ).call

    expect(retry_result.run.status).to eq('applied')
    expect(missing_candidate.reload.source_status).to eq('missing')
  end

  it '未掲載差分保留runへのCONFIRMなし呼び出しでは成功メタデータを汚さないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H9999',
      shozoku_code: '01',
      term_code: 'A'
    )
    run = analyzed_run(lecture, file_name: 'missing-confirm.csv')
    described_class.new(import_run_id: run.id, confirm: true, confirm_missing: false).call
    previous_finished_at = run.reload.finished_at

    expect do
      described_class.new(import_run_id: run.id, confirm: false, confirm_missing: true).call
    end.to raise_error(described_class::Error, /CONFIRM=true/)

    expect(run.reload).to have_attributes(
      status: 'applied_without_missing',
      error_summary: nil,
      finished_at: previous_finished_at
    )
  end

  it 'run適用後に作成Offeringの曜限が変更された場合はrollbackで削除しないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    run = analyzed_run(lecture)
    described_class.new(import_run_id: run.id, confirm: true).call
    offering = LectureOffering.find_by!(year: 2027, registration_code: '271H2001')
    offering.offering_slots.create!(day: 2, period: 5)

    expect { Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(Syllabus::ImportRollback::Error, /rollbackできません/)

    expect(run.reload.status).to eq('applied')
    expect(offering.reload.offering_slots.pluck(:day, :period)).to include([2, 5])
  end

  it 'run適用後に更新Offeringが変更された場合はrollbackで復元しないこと' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論Ａ', lecturer: '山田 太郎', faculty: 'H:人文学部')
    offering = LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H2001',
      shozoku_code: '01',
      term_code: 'A'
    )
    run = analyzed_run(lecture, term_label: '第2ターム', raw_day_periods: '火3')
    described_class.new(import_run_id: run.id, confirm: true).call
    offering.update_columns(source_title: '適用後の外部変更')

    expect { Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(Syllabus::ImportRollback::Error, /rollbackできません/)

    expect(run.reload.status).to eq('applied')
    expect(offering.reload.source_title).to eq('適用後の外部変更')
  end

  it '複数行runを逆順にrollbackしても昇順manifestのhash検証に成功すること' do
    first_lecture = FactoryBot.create(:lecture, title: '複数行講義A', lecturer: '教員A', faculty: 'H:人文学部')
    second_lecture = FactoryBot.create(:lecture, title: '複数行講義B', lecturer: '教員B', faculty: 'H:人文学部')
    run = analyzed_v2_rows([
                             v2_row(first_lecture, code: '271H3001'),
                             v2_row(second_lecture, code: '271H3002', raw_day_periods: '火3')
                           ])
    described_class.new(import_run_id: run.id, confirm: true).call

    result = Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call

    expect(result.run.status).to eq('rolled_back')
    expect(LectureOffering.where(year: 2027, registration_code: %w[271H3001 271H3002])).to be_empty
  end

  it '解析後にsource列を変更したrunを適用しないこと' do
    run = analyzed_legacy_run(title: '改変前講義', file_name: 'tampered-source.csv')
    row = run.syllabus_import_rows.first
    row.update_columns(source_title: '改変後講義')

    expect { described_class.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(described_class::Error, /解析結果のハッシュ/)
    expect(Lecture.find_by(title: '改変後講義')).to be_nil
  end

  it '完全性判定のerror_countだけを解除したrunを適用しないこと' do
    run = analyzed_legacy_run(title: '完全性判定講義', file_name: 'tampered-completeness.csv')
    run.update_columns(error_count: 1)
    run.update_columns(staged_sha256: run.calculated_staged_sha256)
    run.update_columns(error_count: 0)

    expect { described_class.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(described_class::Error, /解析結果のハッシュ/)
    expect(Lecture.find_by(title: '完全性判定講義')).to be_nil
  end

  it 'manifest内のnilを空文字へ変更したrunを適用しないこと' do
    run = analyzed_legacy_run(title: '型保持講義', file_name: 'tampered-scalar-type.csv')
    row = run.syllabus_import_rows.first
    row.update_columns(source_faculty: nil)
    run.update_columns(staged_sha256: run.calculated_staged_sha256)
    row.update_columns(source_faculty: '')

    expect { described_class.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(described_class::Error, /解析結果のハッシュ/)
    expect(Lecture.find_by(title: '型保持講義')).to be_nil
  end

  it '適用後にactionを変更したrunのrollbackを拒否すること' do
    lecture = FactoryBot.create(:lecture, title: 'action改変講義', lecturer: '教員', faculty: 'H:人文学部')
    run = analyzed_run(lecture, file_name: 'tampered-action.csv')
    described_class.new(import_run_id: run.id, confirm: true).call
    offering = LectureOffering.find_by!(year: 2027, registration_code: '271H2001')
    run.syllabus_import_rows.find_by!(source_row_number: 1).update_columns(action: 'lecture_unchanged')

    expect { Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(Syllabus::ImportRollback::Error, /解析結果のハッシュ/)
    expect(LectureOffering.exists?(offering.id)).to be(true)
  end

  it '適用後にbefore_valuesを変更したrunのrollbackを拒否すること' do
    lecture = FactoryBot.create(:lecture, title: 'before改変講義', lecturer: '教員', faculty: 'H:人文学部')
    run = analyzed_run(lecture, file_name: 'tampered-before.csv')
    described_class.new(import_run_id: run.id, confirm: true).call
    offering = LectureOffering.find_by!(year: 2027, registration_code: '271H2001')
    run.syllabus_import_rows.find_by!(source_row_number: 1).update_columns(before_values: { 'source_title' => '不正な復元値' })

    expect { Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(Syllabus::ImportRollback::Error, /解析結果のハッシュ/)
    expect(LectureOffering.exists?(offering.id)).to be(true)
  end

  it '適用後にapplied IDを変更したrunのrollbackを拒否すること' do
    lecture = FactoryBot.create(:lecture, title: 'result改変講義', lecturer: '教員', faculty: 'H:人文学部')
    run = analyzed_run(lecture, file_name: 'tampered-result.csv')
    described_class.new(import_run_id: run.id, confirm: true).call
    imported = LectureOffering.find_by!(year: 2027, registration_code: '271H2001')
    other = LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H3999',
      shozoku_code: '01',
      term_code: 'A'
    )
    run.syllabus_import_rows.find_by!(source_row_number: 1).update_columns(applied_offering_id: other.id)

    expect { Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(Syllabus::ImportRollback::Error, /適用結果のハッシュ/)
    expect(LectureOffering.exists?(imported.id)).to be(true)
    expect(LectureOffering.exists?(other.id)).to be(true)
  end

  it 'version 1の未適用runは再解析を要求すること' do
    run = analyzed_legacy_run(title: '旧manifest講義', file_name: 'legacy-manifest.csv')
    legacy_hash = run.calculated_staged_sha256(version: 1)
    run.update_columns(staged_payload_version: 1, staged_sha256: legacy_hash)

    expect { described_class.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(described_class::Error, /旧形式.*再解析/)
    expect(run.reload.status).to eq('analyzed')
  end

  it 'version 1で未掲載差分を保留したrunはrollback後の再解析を要求すること' do
    run = analyzed_legacy_run(title: '旧保留run講義', file_name: 'legacy-partial-manifest.csv')
    legacy_hash = run.calculated_staged_sha256(version: 1)
    run.update_columns(
      status: 'applied_without_missing',
      applied_at: Time.current,
      staged_payload_version: 1,
      staged_sha256: legacy_hash
    )

    expect do
      described_class.new(import_run_id: run.id, confirm: true, confirm_missing: true).call
    end.to raise_error(described_class::Error, /rollback.*再解析/)
    expect(run.reload.status).to eq('applied_without_missing')
  end

  it 'version 1で既に適用済みのrunは旧hashを検証してrollbackできること' do
    lecture = FactoryBot.create(:lecture, title: '旧rollback講義', lecturer: '教員', faculty: 'H:人文学部')
    run = analyzed_run(lecture, file_name: 'legacy-rollback.csv')
    described_class.new(import_run_id: run.id, confirm: true).call
    row = run.syllabus_import_rows.find_by!(source_row_number: 1)
    row.update_columns(
      matched_lecture_id: row.applied_lecture_id,
      matched_offering_id: row.applied_offering_id,
      applied_lecture_id: nil,
      applied_offering_id: nil
    )
    run.update_columns(
      staged_payload_version: 1,
      staged_sha256: run.calculated_staged_sha256(version: 1),
      applied_result_sha256: nil
    )

    result = Syllabus::ImportRollback.new(import_run_id: run.id, confirm: true).call

    expect(result.run.status).to eq('rolled_back')
    expect(LectureOffering.find_by(year: 2027, registration_code: '271H2001')).to be_nil
  end

  it '解析後に照合Lectureのidentityが変わった場合はOfferingを更新しないこと' do
    lecture = FactoryBot.create(:lecture, title: '照合元講義', lecturer: '教員', faculty: 'H:人文学部')
    offering = LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H2001',
      shozoku_code: '01',
      term_code: 'A'
    )
    run = analyzed_run(lecture, file_name: 'changed-lecture.csv', term_label: '第2ターム')
    lecture.update!(title: '解析後に変更された講義')

    expect { described_class.new(import_run_id: run.id, confirm: true).call }
      .to raise_error(described_class::Error, /normalized_keyが解析時から変わっています/)
    expect(offering.reload.term_code).to eq('A')
  end

  it 'Lecture作成競合時はunique違反後にcanonical Lectureを再取得すること' do
    run = analyzed_legacy_run(title: '競合講義', file_name: 'concurrent-lecture.csv')
    row = run.syllabus_import_rows.first
    concurrent = FactoryBot.create(:lecture, title: '競合講義', lecturer: '山田太郎', faculty: 'H:人文学部')
    initial_relation = instance_double(ActiveRecord::Relation)
    locked_relation = instance_double(ActiveRecord::Relation)
    allow(Lecture).to receive(:canonical).and_return(initial_relation)
    allow(initial_relation).to receive(:find_by).with(normalized_key: row.normalized_key).and_return(nil)
    allow(initial_relation).to receive(:lock).and_return(locked_relation)
    allow(locked_relation).to receive(:find_by).with(normalized_key: row.normalized_key).and_return(concurrent)
    allow(Lecture).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, 'duplicate normalized_key')
    applier = described_class.new(import_run_id: run.id, confirm: true)

    expect(applier.send(:create_lecture!, row)).to eq(concurrent)
  end
end
