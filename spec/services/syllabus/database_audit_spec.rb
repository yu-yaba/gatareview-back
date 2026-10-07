# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Syllabus::DatabaseAudit do
  it '保存済みnormalized_keyではなく講義情報から再計算して重複を検出すること' do
    first = FactoryBot.create(
      :lecture,
      title: '心理学概論A',
      lecturer: '山田 太郎',
      faculty: 'H:人文学部'
    )
    second = FactoryBot.create(
      :lecture,
      title: '別の講義',
      lecturer: '別の教員',
      faculty: '別の所属'
    )
    first.update_columns(normalized_key: 'e' * 64)
    second.update_columns(
      title: '心理学概論Ａ',
      lecturer: '山田太郎',
      faculty: 'H:人文学部',
      normalized_key: 'f' * 64
    )

    result = described_class.new.call
    computed_key = Syllabus::Normalizer.lecture_key(
      title: first.title,
      lecturer: first.lecturer,
      faculty: first.faculty
    )

    expect(result.normalized_lecture_duplicates).to eq(computed_key => [first.id, second.id])
    expect(result.normalized_key_mismatches.pluck(:lecture_id)).to contain_exactly(first.id, second.id)
    expect { Syllabus::LegacyDataBackfill.new(confirm: true).call }
      .to raise_error(Syllabus::LegacyDataBackfill::Error, /normalized_lecture_duplicates/)
    expect(first.reload.normalized_key).to eq('e' * 64)
    expect(second.reload.normalized_key).to eq('f' * 64)
  end

  it '重複しない保存済みnormalized_keyのずれはbackfillで修正すること' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論', lecturer: '山田 太郎', faculty: 'H:人文学部')
    expected_key = lecture.normalized_key
    lecture.update_columns(normalized_key: 'e' * 64)

    result = Syllabus::LegacyDataBackfill.new(confirm: true).call

    expect(result.lectures_updated).to eq(1)
    expect(lecture.reload.normalized_key).to eq(expected_key)
  end

  it '正規化後に空になる空白だけの講義識別子を検出すること' do
    lecture = FactoryBot.create(:lecture, title: '心理学概論', lecturer: '山田 太郎', faculty: 'H:人文学部')
    lecture.update_columns(title: " \t　")

    result = described_class.new.call

    expect(result.lectures_with_missing_identity).to include(lecture.id)
    expect { Syllabus::LegacyDataBackfill.new(confirm: true).call }
      .to raise_error(Syllabus::LegacyDataBackfill::Error, /lectures_with_missing_identity/)
  end
end
