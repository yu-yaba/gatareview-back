# frozen_string_literal: true

class Lecture < ApplicationRecord
  # Keep already-added, unused feature columns out of the existing API.
  self.ignored_columns += %w[normalized_key merged_into_lecture_id merged_at]

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

  def self.as_json_reviews(lectures)
    records = lectures.select(:id, :title, :lecturer, :faculty, :created_at, :updated_at).to_a
    return [] if records.empty?

    statistics = Review.where(lecture_id: records.map(&:id))
                       .group(:lecture_id)
                       .pluck(:lecture_id, Arel.sql('AVG(rating)'), Arel.sql('COUNT(*)'))
                       .to_h { |id, average, count| [id, [average, count]] }

    records.map do |lecture|
      average, count = statistics.fetch(lecture.id.to_s, [0, 0])
      {
        id: lecture.id,
        title: lecture.title,
        lecturer: lecture.lecturer,
        faculty: lecture.faculty,
        created_at: lecture.created_at,
        updated_at: lecture.updated_at,
        avg_rating: (average || 0).round(1),
        review_count: count
      }
    end
  end

  def as_json_with_reviews
    avg_rating, review_count = reviews.pick(Arel.sql('AVG(rating)'), Arel.sql('COUNT(*)'))

    # as_jsonで基本属性を取得し、追加情報をマージ
    as_json.merge(
      avg_rating: (avg_rating || 0).round(1),
      review_count: review_count
    )
  end

  private

  def strip_attributes
    self.title = title&.strip
    self.lecturer = lecturer&.strip
    self.faculty = faculty&.strip
  end
end
