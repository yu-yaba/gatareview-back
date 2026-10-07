# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Review, type: :model do
  describe 'content validation' do
    [30, 1000].each do |length|
      it "#{length}文字の本文を受理すること" do
        expect(FactoryBot.build(:review, content: 'あ' * length)).to be_valid
      end
    end

    [0, 29, 1001].each do |length|
      it "#{length}文字の本文を拒否すること" do
        review = FactoryBot.build(:review, content: 'あ' * length)
        expect(review).not_to be_valid
        expect(review.errors[:content]).to be_present
      end
    end
  end

  describe 'rating validation' do
    [0.5, 1, 3.5, 5, 5.0].each do |rating|
      it "#{rating}の0.5刻みの評価を受理すること" do
        expect(FactoryBot.build(:review, rating: rating)).to be_valid
      end
    end

    [nil, 0, 0.1, 5.5, 999, -1, 3.3, '5invalid', 'NaN', 'Infinity'].each do |rating|
      it "不正な評価#{rating.inspect}を拒否すること" do
        review = FactoryBot.build(:review, rating: rating)
        expect(review).not_to be_valid
        expect(review.errors[:rating]).to be_present
      end
    end
  end

  describe 'detail choices and legacy compatibility' do
    {
      textbook: %w[必要 不要 どちらでも その他・不明],
      attendance: %w[毎回確認 たまに確認 なし その他・不明],
      grading_type: %w[テストのみ レポートのみ テスト,レポート その他・不明],
      content_difficulty: %w[とても楽 楽 普通 難 とても難しい],
      content_quality: %w[とても良い 良い 普通 悪い とても悪い]
    }.each do |attribute, choices|
      it "#{attribute}の画面上の選択肢と任意の空欄を受理すること" do
        [*choices, '', nil].each do |choice|
          expect(FactoryBot.build(:review, attribute => choice)).to be_valid
        end
      end

      it "#{attribute}の未定義の選択肢を拒否すること" do
        review = FactoryBot.build(:review, attribute => '未定義の入力')
        expect(review).not_to be_valid
        expect(review.errors[attribute]).to be_present
      end
    end

    it '変更していない旧データを保持して本文だけを更新できること' do
      review = FactoryBot.create(:review)
      review.update_columns(rating: 3.3, content: '旧データの短い本文', textbook: '旧教科書選択肢')

      expect(review.reload.update(content: 'あ' * 30)).to be(true)
      expect(review.reload).to have_attributes(rating: 3.3, textbook: '旧教科書選択肢', content: 'あ' * 30)
    end

    it '旧データでも変更する属性には現在の入力制約を適用すること' do
      review = FactoryBot.create(:review)
      review.update_columns(rating: 3.3, content: '旧データの短い本文', textbook: '旧教科書選択肢')

      expect(review.reload.update(rating: 4.4, content: '別の短文', textbook: '別の未定義値')).to be(false)
      expect(review.errors.attribute_names).to include(:rating, :content, :textbook)
      expect(review.reload).to have_attributes(rating: 3.3, content: '旧データの短い本文', textbook: '旧教科書選択肢')
    end
  end
end
