# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Syllabus::DomainReferenceIntegrity do
  it '対象外のReviewや時間割が追加・削除されても対象Offeringの検証結果を変えないこと' do
    target_lecture = FactoryBot.create(:lecture)
    target_offering = LectureOffering.create!(
      lecture: target_lecture,
      year: 2027,
      registration_code: '271H4001',
      shozoku_code: '01',
      term_code: 'A'
    )
    unrelated_lecture = FactoryBot.create(:lecture)
    unrelated_review = FactoryBot.create(:review, lecture: unrelated_lecture)

    expect(described_class.valid_for_offerings?([target_offering.id])).to be(true)

    unrelated_review.destroy!
    FactoryBot.create(:review, lecture: unrelated_lecture)

    expect(described_class.valid_for_offerings?([target_offering.id])).to be(true)
  end

  it '対象OfferingとReviewのLecture・年度・termが矛盾する場合は拒否すること' do
    lecture = FactoryBot.create(:lecture)
    offering = LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H4002',
      shozoku_code: '01',
      term_code: 'A'
    )
    review = FactoryBot.create(
      :review,
      lecture:,
      lecture_offering: offering,
      period_year: '2027',
      period_term: '1ターム'
    )
    review.update_columns(term_code: 'B')

    expect(described_class.valid_for_offerings?([offering.id])).to be(false)
  end
end
