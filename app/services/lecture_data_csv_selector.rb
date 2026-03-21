# frozen_string_literal: true

class LectureDataCsvSelector
  YEARLY_CSV_PATTERN = /^lectureData_(\d{4})\.csv$/

  class << self
    def latest_path(root: Rails.root)
      latest_yearly_path(root) || root.join('lectureData.csv')
    end

    private

    def latest_yearly_path(root)
      yearly_files = Dir[root.join('lectureData_*.csv')].filter_map do |path|
        match = File.basename(path).match(YEARLY_CSV_PATTERN)
        [match[1].to_i, Pathname.new(path)] if match
      end

      yearly_files.max_by(&:first)&.last
    end
  end
end
