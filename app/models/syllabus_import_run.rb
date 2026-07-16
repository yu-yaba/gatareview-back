# frozen_string_literal: true

class SyllabusImportRun < ApplicationRecord
  STATUSES = %w[analyzing analyzed applying applied_without_missing applied failed rolled_back].freeze
  SOURCE_TYPES = %w[csv_v2 legacy_csv].freeze

  has_many :syllabus_import_rows, dependent: :destroy
  has_many :first_seen_offerings, class_name: 'LectureOffering', foreign_key: :first_seen_import_run_id, dependent: :nullify, inverse_of: :first_seen_import_run
  has_many :last_seen_offerings, class_name: 'LectureOffering', foreign_key: :last_seen_import_run_id, dependent: :nullify, inverse_of: :last_seen_import_run
  has_many :missing_since_offerings, class_name: 'LectureOffering', foreign_key: :missing_since_import_run_id, dependent: :nullify, inverse_of: :missing_since_import_run

  validates :year, presence: true, inclusion: { in: 2000..2100 }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :source_file_name, :source_sha256, :started_at, presence: true
  validates :source_sha256, length: { is: 64 }
  validates :status, inclusion: { in: STATUSES }

  scope :applied, -> { where(status: 'applied') }
  scope :applied_to_domain, -> { where(status: %w[applied_without_missing applied]) }

  def applicable?
    status == 'analyzed' && error_count.zero? && conflict_count.zero?
  end

  def missing_completion_pending?
    status == 'applied_without_missing'
  end

  def applied_to_domain?
    %w[applied_without_missing applied].include?(status)
  end

  def calculated_staged_sha256
    payload = syllabus_import_rows.order(:sequence_number).pluck(
      :sequence_number, :action, :row_checksum, :before_values, :after_values
    )
    Syllabus::Normalizer.checksum(payload)
  end
end
