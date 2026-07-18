# frozen_string_literal: true

class SyllabusImportRun < ApplicationRecord
  STAGED_PAYLOAD_VERSION = 2
  STAGED_RUN_ATTRIBUTES = %w[
    year
    source_type
    source_file_name
    source_size_bytes
    source_sha256
    staged_payload_version
    total_rows
    valid_rows
    new_lectures_count
    new_offerings_count
    updated_offerings_count
    unchanged_offerings_count
    missing_offerings_count
    conflict_count
    warning_count
    error_count
    faculty_counts
  ].freeze
  STAGED_ROW_ATTRIBUTES = %w[
    sequence_number
    source_row_number
    year
    registration_code
    source_title
    source_lecturer
    source_faculty
    normalized_key
    shozoku_code
    semester_label
    term_label
    term_code
    raw_day_periods
    schedule_kind
    action
    matched_lecture_id
    matched_offering_id
    messages
    before_values
    after_values
    row_checksum
  ].freeze

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

  def calculated_staged_sha256(rows: nil, version: staged_payload_version)
    records = (rows || syllabus_import_rows.order(:sequence_number).to_a).sort_by(&:sequence_number)
    payload = if version.to_i >= STAGED_PAYLOAD_VERSION
                {
                  'run' => attributes.slice(*STAGED_RUN_ATTRIBUTES),
                  'rows' => records.map { |row| row.attributes.slice(*STAGED_ROW_ATTRIBUTES) }
                }
              else
                records.map do |row|
                  [row.sequence_number, row.action, row.row_checksum, row.before_values, row.after_values]
                end
              end
    if version.to_i >= STAGED_PAYLOAD_VERSION
      Syllabus::Normalizer.typed_checksum(payload)
    else
      Syllabus::Normalizer.checksum(payload)
    end
  end

  def calculated_applied_result_sha256(rows: nil)
    records = (rows || syllabus_import_rows.order(:sequence_number).to_a).sort_by(&:sequence_number)
    payload = records.map do |row|
      [row.sequence_number, row.applied_lecture_id, row.applied_offering_id]
    end
    Syllabus::Normalizer.typed_checksum(payload)
  end
end
