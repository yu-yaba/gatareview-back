# frozen_string_literal: true

class Review < ApplicationRecord
  belongs_to :lecture
  belongs_to :user, optional: true # 既存データとの互換性のため一時的にoptional
  has_many :thanks, dependent: :destroy

  validates :rating, uniqueness: { scope: %i[ content lecture_id textbook attendance
                                              grading_type content_difficulty content_quality
                                              period_year period_term] }
end
