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

  desc 'Import lectures from a CSV file without using db:seed'
  task import_csv: :environment do
    importer = Syllabus::LectureCsvImporter.new(csv_path: ENV['CSV_PATH'])
    result = importer.call

    puts "CSV imported: #{result.path}"
    puts "Rows processed: #{result.total_rows_processed}"
    puts "Rows skipped: #{result.skipped_rows_count}"
    puts "Rows prepared: #{result.prepared_rows_count}"
    puts "Lecture count before: #{result.lecture_count_before}"
    puts "Lecture count after: #{result.lecture_count_after}"
    puts "Rows inserted: #{result.inserted_count}"
    puts "Rows ignored (existing or duplicate): #{result.ignored_count}"
    result.faculty_counts.each do |faculty, count|
      puts "#{faculty}: #{count}"
    end
    puts 'No db:seed or test lecture seeding was executed.'
  rescue ArgumentError, Syllabus::LectureCsvImporter::Error => e
    warn e.message
    exit 1
  end

  desc 'Show lecture counts before or after an import'
  task count: :environment do
    if ENV['FACULTY'].present?
      puts "#{ENV['FACULTY']}: #{Lecture.where(faculty: ENV['FACULTY']).count}"
    else
      puts "Total lectures: #{Lecture.count}"
      Lecture.group(:faculty).count.sort.each do |faculty, count|
        puts "#{faculty}: #{count}"
      end
    end
  end
end
