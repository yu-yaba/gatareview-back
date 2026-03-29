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
end
