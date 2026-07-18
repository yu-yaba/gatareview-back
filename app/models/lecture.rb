# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews
  has_many :bookmarks, dependent: :destroy
  has_many :lecture_offerings, dependent: :destroy
  has_many :timetable_entries, dependent: :destroy
  has_many :lecture_aliases, dependent: :destroy
  belongs_to :merged_into_lecture, class_name: 'Lecture', optional: true
  has_many :merged_lectures, class_name: 'Lecture', foreign_key: :merged_into_lecture_id,
                             dependent: :nullify, inverse_of: :merged_into_lecture

  # シラバスリンク・曜限バッジ表示の代表として使う最新年度の開講
  def latest_offering
    if association(:lecture_offerings).loaded?
      return lecture_offerings.select(&:active?).max_by(&:year)
    end

    lecture_offerings.active.order(year: :desc).first
  end

  def offering_json(offering = latest_offering)
    return nil unless offering

    {
      id: offering.id,
      year: offering.year,
      term_label: offering.term_label,
      term_code: offering.term_code,
      term_numbers: offering.term_numbers,
      schedule_kind: offering.schedule_kind,
      source_title: offering.source_title,
      source_lecturer: offering.source_lecturer,
      slots: offering.offering_slots.sort_by { |slot| [slot.day, slot.period] }.map { |slot| { day: slot.day, period: slot.period } },
      syllabus_url: offering.syllabus_url,
      details: offering.lecture_offering_detail&.as_json(
        only: %i[credits target_years campus language delivery_method subject_category]
      )
    }
  end
  
  before_validation :strip_attributes
  before_validation :set_normalized_key
  
  validates :title, :lecturer, :faculty, presence: true
  validates :title, uniqueness: { scope: %i[lecturer faculty] }
  validates :normalized_key, uniqueness: true, allow_nil: true

  scope :canonical, -> { where(merged_into_lecture_id: nil) }

  # 検索用スコープ（MySQL対応：LIKEを使用した大文字小文字を区別しない検索）
  scope :search_by_title_and_lecturer, ->(query) {
    sanitized_query = "%#{sanitize_sql_like(query.to_s)}%"
    alias_lecture_ids = LectureAlias.where('title LIKE ? OR lecturer LIKE ?', sanitized_query, sanitized_query).select(:lecture_id)
    offering_lecture_ids = LectureOffering.active
                                            .where('source_title LIKE ? OR source_lecturer LIKE ?', sanitized_query, sanitized_query)
                                            .select(:lecture_id)

    where('lectures.title LIKE :query OR lectures.lecturer LIKE :query', query: sanitized_query)
      .or(where(id: alias_lecture_ids))
      .or(where(id: offering_lecture_ids))
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

  def self.as_json_reviews(lectures, offerings_by_lecture_id: nil)
    lecture_records = lectures.to_a

    # 一度に全ての平均評価を取得
    avg_ratings = average_rating(lecture_records)

    # レビュー数も一度に取得（必要な場合のみ）
    # DISTINCTクエリの場合、pluckが問題を起こす可能性があるため安全に取得
    lecture_ids = lecture_records.map(&:id)
    review_counts = Review.where(lecture_id: lecture_ids)
                          .group(:lecture_id)
                          .count

    # 必要なカラムのみ選択して効率化
    lecture_records.map do |lecture|
      offering = if offerings_by_lecture_id
                   offerings_by_lecture_id.fetch(lecture.id)
                 else
                   lecture.latest_offering
                 end

      {
        id: lecture.id,
        title: lecture.title,
        lecturer: lecture.lecturer,
        faculty: lecture.faculty,
        created_at: lecture.created_at,
        updated_at: lecture.updated_at,
        avg_rating: (avg_ratings[lecture.id.to_s] || 0).round(1),
        review_count: review_counts[lecture.id.to_s] || 0,
        offering: lecture.offering_json(offering)
      }
    end
  end

  def as_json_with_reviews(offering: latest_offering)
    # 関連するレビューの平均評価と数を計算
    # to_f を使って小数点以下の除算を保証
    avg_rating = reviews.average(:rating) || 0
    review_count = reviews.count

    # as_jsonで基本属性を取得し、追加情報をマージ
    as_json.merge(
      avg_rating: avg_rating.round(1),
      review_count: review_count,
      offering: offering_json(offering)
    )
  end

  private

  def strip_attributes
    self.title = title&.strip
    self.lecturer = lecturer&.strip
    self.faculty = faculty&.strip
  end

  def set_normalized_key
    if merged_into_lecture_id.present?
      self.normalized_key = nil
      return
    end

    return if title.blank? || lecturer.blank? || faculty.blank?

    self.normalized_key = Syllabus::Normalizer.lecture_key(title:, lecturer:, faculty:)
  end
end
