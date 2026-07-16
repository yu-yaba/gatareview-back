# frozen_string_literal: true

class SyllabusOrganization < ApplicationRecord
  DEFAULTS = [
    { code: '01', name: '人文学部', faculty_label: 'H:人文学部' },
    { code: '03', name: '教育学部', faculty_label: 'K:教育学部' },
    { code: '04', name: '法学部', faculty_label: 'L:法学部' },
    { code: '0C', name: '経済科学部', faculty_label: 'E:経済科学部' },
    { code: '06', name: '理学部', faculty_label: 'S:理学部' },
    { code: '07', name: '医学部', faculty_label: 'M:医学部' },
    { code: '08', name: '歯学部', faculty_label: 'D:歯学部' },
    { code: '09', name: '工学部', faculty_label: 'T:工学部' },
    { code: '0A', name: '農学部', faculty_label: 'A:農学部' },
    { code: '0B', name: '創生学部', faculty_label: 'X:創生学部' },
    { code: '84', name: '教養科目', faculty_label: 'G:教養科目' }
  ].freeze

  has_many :lecture_offerings, dependent: :restrict_with_error

  validates :code, :name, :faculty_label, :valid_from_year, presence: true
  validates :code, uniqueness: { scope: :valid_from_year }
  validate :valid_year_range

  scope :enabled, -> { where(enabled_for_import: true) }
  scope :for_year, lambda { |year|
    where('valid_from_year <= ?', year).where('valid_until_year IS NULL OR valid_until_year >= ?', year)
  }

  def self.seed_defaults!(valid_from_year: 2026)
    DEFAULTS.each do |attributes|
      find_or_create_by!(code: attributes[:code], valid_from_year:) do |organization|
        organization.assign_attributes(attributes.merge(enabled_for_import: true))
      end
    end
  end

  private

  def valid_year_range
    return if valid_until_year.blank? || valid_from_year.blank? || valid_until_year >= valid_from_year

    errors.add(:valid_until_year, 'は開始年度以降にしてください')
  end
end
