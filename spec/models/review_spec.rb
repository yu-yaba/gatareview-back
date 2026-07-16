# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Review, type: :model do
  describe 'content validation' do
    it '30文字未満でも有効なこと' do
      review = FactoryBot.build(:review, content: '短い感想です')

      expect(review).to be_valid
    end

    it '1000文字を超えると無効なこと' do
      review = FactoryBot.build(:review, content: 'あ' * 1001)

      expect(review).not_to be_valid
      expect(review.errors[:content]).to include('is too long (maximum is 1000 characters)')
    end
  end

  describe 'syllabus references' do
    let(:lecture) { FactoryBot.create(:lecture) }
    let!(:offering) do
      LectureOffering.create!(
        lecture: lecture,
        year: 2026,
        registration_code: '261H2001',
        shozoku_code: '01',
        term_code: 'A'
      )
    end

    it 'writes the additive lecture reference and assigns a unique offering' do
      review = FactoryBot.build(:review, lecture: lecture, academic_year: 2026, term_code: 'A')

      expect(review).to be_valid
      expect(review.lecture_id_bigint).to eq(lecture.id)
      expect(review.lecture_offering).to eq(offering)
    end

    it 'rejects an offering whose term does not match the review' do
      review = FactoryBot.build(
        :review,
        lecture: lecture,
        lecture_offering: offering,
        academic_year: 2026,
        term_code: 'B'
      )

      expect(review).not_to be_valid
      expect(review.errors[:lecture_offering]).to include('は受講タームと一致しません')
    end
  end
end
