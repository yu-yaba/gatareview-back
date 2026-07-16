# frozen_string_literal: true

class LectureAlias < ApplicationRecord
  MATCH_METHODS = %w[exact alias manual].freeze

  belongs_to :lecture
  belongs_to :created_from_import_run, class_name: 'SyllabusImportRun', optional: true

  before_validation :set_normalized_key

  validates :title, :lecturer, :faculty, :normalized_key, presence: true
  validates :normalized_key, uniqueness: true
  validates :match_method, inclusion: { in: MATCH_METHODS }

  scope :confirmed, -> { where(confirmed: true) }

  private

  def set_normalized_key
    self.normalized_key = Syllabus::Normalizer.lecture_key(title:, lecturer:, faculty:)
  end
end
