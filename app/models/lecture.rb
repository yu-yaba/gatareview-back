# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews
  validates :title, :lecturer, :faculty, presence: true
  validates :title, uniqueness: { scope: %i[lecturer faculty] }

  def self.average_rating(lectures)
    # idのカラムのみを取得して、lecture_idsという配列をつくる。
    lecture_ids = lectures.pluck(:id)

    # whereで、Reviewモデルのlecture_idと対応したlectureを絞り込む
    # 絞り込んだものをgroup化してaverageで平均評価を出している
    Review.where(lecture_id: lecture_ids).group(:lecture_id).average(:rating)
  end

  def self.as_json_reviews(lectures)
    avg_ratings = average_rating(lectures)
    lectures.map do |lecture|
      # lectureの属性を取り出してハッシュを生成
      lecture_attributes = lecture.attributes
      avg_rating = avg_ratings[lecture.id.to_s] || 0
      lecture_attributes[:avg_rating] = avg_rating.round(1)
      lecture_attributes[:reviews] = lecture.reviews.map do |review|
        {
          created_at: review.created_at,
        }
      end
      lecture_attributes
    end
  end
end
