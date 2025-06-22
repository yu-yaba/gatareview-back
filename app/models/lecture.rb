# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews
  validates :title, :lecturer, :faculty, presence: true
  validates :title, uniqueness: { scope: %i[lecturer faculty] }

  # 検索用スコープ
  scope :search_by_title_and_lecturer, ->(query) {
    where("title LIKE ? OR lecturer LIKE ?", "%#{query}%", "%#{query}%")
  }

  def self.average_rating(lectures)
    # 効率的な平均評価計算
    lecture_ids = lectures.is_a?(ActiveRecord::Relation) ? lectures.pluck(:id) : lectures.map(&:id)
    return {} if lecture_ids.empty?

    Review.where(lecture_id: lecture_ids)
          .group(:lecture_id)
          .average(:rating)
  end

  def self.as_json_reviews(lectures)
    # 一度に全ての平均評価を取得
    avg_ratings = average_rating(lectures)
    
    # レビュー数も一度に取得
    lecture_ids = lectures.is_a?(ActiveRecord::Relation) ? lectures.pluck(:id) : lectures.map(&:id)
    review_counts = Review.where(lecture_id: lecture_ids)
                         .group(:lecture_id)
                         .count
    
    lectures.map do |lecture|
      lecture_attributes = lecture.attributes
      avg_rating = avg_ratings[lecture.id] || 0
      lecture_attributes[:avg_rating] = avg_rating.round(1)
      # レビューの詳細は不要なので、件数のみ
      lecture_attributes[:review_count] = review_counts[lecture.id] || 0
      lecture_attributes
    end
  end
end
