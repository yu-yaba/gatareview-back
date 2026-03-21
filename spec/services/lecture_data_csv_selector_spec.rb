# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe LectureDataCsvSelector do
  describe '.latest_path' do
    it 'returns the latest yearly lecture data csv when multiple yearly files exist' do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        root.join('lectureData_2024.csv').write('')
        root.join('lectureData_2026.csv').write('')
        root.join('lectureData_2025.csv').write('')

        expect(described_class.latest_path(root: root)).to eq(root.join('lectureData_2026.csv'))
      end
    end

    it 'falls back to lectureData.csv when no yearly csv exists' do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        root.join('lectureData.csv').write('')

        expect(described_class.latest_path(root: root)).to eq(root.join('lectureData.csv'))
      end
    end

    it 'ignores files that do not match the yearly csv naming pattern' do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        root.join('lectureData.csv').write('')
        root.join('lectureData_latest.csv').write('')
        root.join('lectureData_2026_backup.csv').write('')
        root.join('lectureData_2025.csv').write('')

        expect(described_class.latest_path(root: root)).to eq(root.join('lectureData_2025.csv'))
      end
    end
  end
end
