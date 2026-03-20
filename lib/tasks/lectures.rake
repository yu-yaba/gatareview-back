# frozen_string_literal: true

namespace :lectures do
  desc 'Export lecture CSV from Niigata University syllabus without seeding the database'
  task export_csv: :environment do
    exporter = Syllabus::LectureCsvExporter.new(
      year: ENV['YEAR'],
      output_dir: ENV['OUTPUT_DIR'].presence || Rails.root
    )

    result = exporter.call

    puts "CSV generated: #{result.path}"
    puts "Rows exported: #{result.row_count}"
    result.faculty_counts.each do |faculty, count|
      puts "#{faculty}: #{count}"
    end
    puts 'No seed or database import was executed.'
  rescue ArgumentError, Syllabus::LectureCsvExporter::Error => e
    warn e.message
    exit 1
  end
end
