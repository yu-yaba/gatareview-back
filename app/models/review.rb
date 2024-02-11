# frozen_string_literal: true

class Review < ApplicationRecord
  belongs_to :lecture
  validates :rating, uniqueness: { scope: %i[ content lecture_id textbook attendance
                                              grading_type content_difficulty content_quality
                                              period_year period_term] }
end
