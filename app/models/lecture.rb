# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews
  has_many :bookmarks, dependent: :destroy
  
  before_validation :strip_attributes
  
  validates :title, :lecturer, :faculty, presence: true
  validates :title, uniqueness: { scope: %i[lecturer faculty] }

  # 検索用スコープ（MySQL対応：LIKEを使用した大文字小文字を区別しない検索）
  scope :search_by_title_and_lecturer, ->(query) {
    sanitized_query = "%#{sanitize_sql_like(query.to_s)}%"
    # MySQLではLIKEがデフォルトで大文字小文字を区別しないため、ILIKEの代わりにLIKEを使用
    where("title LIKE ? OR lecturer LIKE ?", sanitized_query, sanitized_query)
  }

  def self.average_rating(lectures)
    # 効率的な平均評価計算
    # DISTINCTクエリの場合、pluckが問題を起こす可能性があるため安全に取得
    lecture_ids = if lectures.is_a?(ActiveRecord::Relation)
                    # DISTINCTクエリの場合は一度materializeしてからmap
                    lectures.to_a.map(&:id)
                  else
                    lectures.map(&:id)
                  end
    return {} if lecture_ids.empty?

    Review.where(lecture_id: lecture_ids)
          .group(:lecture_id)
          .average(:rating)
  end

  def self.as_json_reviews(lectures)
    # 一度に全ての平均評価を取得
    avg_ratings = average_rating(lectures)

    # レビュー数も一度に取得（必要な場合のみ）
    # DISTINCTクエリの場合、pluckが問題を起こす可能性があるため安全に取得
    lecture_ids = if lectures.is_a?(ActiveRecord::Relation)
                    # DISTINCTクエリの場合は一度materializeしてからpluck
                    lectures.to_a.map(&:id)
                  else
                    lectures.map(&:id)
                  end
    review_counts = Review.where(lecture_id: lecture_ids)
                          .group(:lecture_id)
                          .count

    # 必要なカラムのみ選択して効率化
    lectures.select(:id, :title, :lecturer, :faculty, :created_at, :updated_at).map do |lecture|
      {
        id: lecture.id,
        title: lecture.title,
        lecturer: lecture.lecturer,
        faculty: lecture.faculty,
        created_at: lecture.created_at,
        updated_at: lecture.updated_at,
        avg_rating: (avg_ratings[lecture.id.to_s] || 0).round(1),
        review_count: review_counts[lecture.id.to_s] || 0
      }
    end
  end

  private

  def strip_attributes
    self.title = title&.strip
    self.lecturer = lecturer&.strip
    self.faculty = faculty&.strip
  end
end
