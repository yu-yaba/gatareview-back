# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lecture, type: :model do
  def record_selects
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

      statements << payload.fetch(:sql) if payload.fetch(:sql).match?(/\ASELECT/i)
    end
    yield statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe '.as_json_reviews' do
    it '授業数が増えても2回の読み取り以内で、並び順・平均点・件数を返すこと' do
      lectures = FactoryBot.create_list(:lecture, 3)
      FactoryBot.create(:review, lecture: lectures.first, rating: 3)
      FactoryBot.create(:review, lecture: lectures.first, rating: 4)
      FactoryBot.create(:review, lecture: lectures.second, rating: 4.5)

      record_selects do |statements|
        result = described_class.as_json_reviews(described_class.order(id: :desc))

        expect(result.map { |lecture| lecture.fetch(:id) }).to eq(lectures.reverse.map(&:id))
        expect(result.map { |lecture| lecture.values_at(:avg_rating, :review_count) }).to eq(
          [[0, 0], [4.5, 1], [3.5, 2]]
        )
        expect(result.first.keys).to contain_exactly(
          :id, :title, :lecturer, :faculty, :created_at, :updated_at, :avg_rating, :review_count
        )
        expect(statements.size).to be <= 2
      end
    end

    it '対象授業がない場合はレビューを集計しないこと' do
      record_selects do |statements|
        expect(described_class.as_json_reviews(described_class.where(id: -1))).to eq([])
        expect(statements.none? { |sql| sql.include?('FROM `reviews`') }).to be(true)
      end
    end

    it '評価が欠けた既存レビューも件数に含め、平均点の空値は0にすること' do
      lecture = FactoryBot.create(:lecture)
      review = FactoryBot.create(:review, lecture: lecture)
      review.update_column(:rating, nil)

      result = described_class.as_json_reviews(described_class.where(id: lecture.id)).first

      expect(result).to include(avg_rating: 0, review_count: 1)
    end
  end

  describe '#as_json_with_reviews' do
    it '平均点と件数を1回の読み取りで取得すること' do
      lecture = FactoryBot.create(:lecture)
      FactoryBot.create(:review, lecture: lecture, rating: 3)
      FactoryBot.create(:review, lecture: lecture, rating: 4)

      record_selects do |statements|
        result = lecture.as_json_with_reviews

        expect(result).to include(avg_rating: 3.5, review_count: 2)
        expect(statements.size).to eq(1)
      end
    end

    it 'レビューがない授業の平均点と件数は0であること' do
      lecture = FactoryBot.create(:lecture)

      expect(lecture.as_json_with_reviews).to include(avg_rating: 0, review_count: 0)
    end
  end
end
