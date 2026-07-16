# frozen_string_literal: true

class LectureOfferingDetail < ApplicationRecord
  belongs_to :lecture_offering

  validates :lecture_offering_id, uniqueness: true
  validates :credits, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
