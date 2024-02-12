# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews
  validates :title, :lecturer, :faculty, presence: true
  validates :title, uniqueness: { scope: %i[lecturer faculty] }

  def self.average_rating(lectures)
    lecture_ids = lectures.pluck(:id)
    Review.where(lecture_id: lecture_ids).group(:lecture_id).average(:rating)
  end

  def self.as_json_reviews(lectures)
    avg_ratings = average_rating(lectures)
    lectures.map do |lecture|
      lecture_attributes = lecture.attributes
      avg_rating = avg_ratings[lecture.id.to_s] || 0
      lecture_attributes[:avg_rating] = avg_rating.round(1)
      lecture_attributes[:reviews] = lecture.reviews.map do |review|
        {
          id: review.id,
          content: review.content,
          rating: review.rating,
          created_at: review.created_at,
          updated_at: review.updated_at
        }
      end
      lecture_attributes
    end
  end
end
