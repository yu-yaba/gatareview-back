# frozen_string_literal: true

class Review < ApplicationRecord
  PERIOD_TERM_TO_CODE = {
    '1ターム' => 'A',
    '2ターム' => 'B',
    '1, 2ターム' => 'E',
    '3ターム' => 'C',
    '4ターム' => 'D',
    '3, 4ターム' => 'F',
    '通年' => '3',
    '集中' => '4'
  }.freeze

  belongs_to :lecture
  belongs_to :lecture_reference, class_name: 'Lecture', foreign_key: :lecture_id_bigint, optional: true
  belongs_to :lecture_offering, optional: true
  belongs_to :user, optional: true, counter_cache: true
  has_many :thanks, dependent: :destroy

  before_validation :populate_syllabus_references
  before_validation :assign_unambiguous_offering
  before_validation :populate_references_from_offering

  validates :rating, presence: true
  validates :content, presence: true, length: { maximum: 1000 }

  validates :user_id, uniqueness: { scope: :lecture_id, allow_nil: true, message: 'は同じ講義に複数のレビューを投稿できません' }
  validates :academic_year, inclusion: { in: 2000..2100 }, allow_nil: true
  validates :term_code, inclusion: { in: LectureOffering::TERM_EXPANSION.keys }, allow_nil: true
  validate :offering_matches_lecture

  private

  def populate_syllabus_references
    self.lecture_id_bigint = Integer(lecture_id, 10) if lecture_id.present? && lecture_id.to_s.match?(/\A\d+\z/)

    if !will_save_change_to_academic_year? && (academic_year.blank? || will_save_change_to_period_year?)
      year = period_year.to_s.match?(/\A\d{4}\z/) ? period_year.to_i : nil
      self.academic_year = year&.between?(2000, 2100) ? year : nil
    end

    if !will_save_change_to_term_code? && (term_code.blank? || will_save_change_to_period_term?)
      self.term_code = PERIOD_TERM_TO_CODE[period_term]
    end
  end

  def offering_matches_lecture
    return if lecture_offering_id.blank?

    unless lecture_offering
      errors.add(:lecture_offering, 'が見つかりません')
      return
    end

    errors.add(:lecture_offering, 'は講義と一致しません') if lecture_offering.lecture_id.to_s != lecture_id.to_s
    if will_save_change_to_lecture_offering_id? && !lecture_offering.active?
      errors.add(:lecture_offering, 'は現在有効ではありません')
    end
    if academic_year.present? && lecture_offering.year != academic_year
      errors.add(:lecture_offering, 'は受講年度と一致しません')
    end
    if term_code.present? && lecture_offering.term_code != term_code
      errors.add(:lecture_offering, 'は受講タームと一致しません')
    end
  end

  def assign_unambiguous_offering
    return if lecture_offering_id.present? || lecture_id.blank? || academic_year.blank?

    scope = LectureOffering.active.where(lecture_id: lecture_id.to_i, year: academic_year)
    scope = scope.where(term_code:) if term_code.present?
    self.lecture_offering = scope.first if scope.one?
  end

  def populate_references_from_offering
    return unless lecture_offering

    self.academic_year ||= lecture_offering.year
    self.term_code ||= lecture_offering.term_code
  end
end
