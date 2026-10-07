# frozen_string_literal: true

class SyllabusImportRow < ApplicationRecord
  ACTIONS = %w[
    create_lecture_and_offering
    create_lecture
    create_offering
    lecture_unchanged
    update_offering
    unchanged
    mark_missing
    conflict
    error
  ].freeze

  belongs_to :syllabus_import_run
  belongs_to :matched_lecture, class_name: 'Lecture', optional: true
  belongs_to :matched_offering, class_name: 'LectureOffering', optional: true
  belongs_to :applied_lecture, class_name: 'Lecture', optional: true
  belongs_to :applied_offering, class_name: 'LectureOffering', optional: true

  validates :sequence_number, presence: true, uniqueness: { scope: :syllabus_import_run_id }
  validates :action, inclusion: { in: ACTIONS }
  validates :row_checksum, presence: true, length: { is: 64 }
end
