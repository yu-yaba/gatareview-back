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
    result = Syllabus::ImportAnalyzer.new(csv_path: ENV['CSV_PATH'], year: ENV['YEAR']).call
    run = result.run

    puts "CSV analyzed. Import run: #{run.id}"
    puts "Status: #{run.status}"
    puts "Rows: #{run.total_rows}, valid=#{run.valid_rows}, errors=#{run.error_count}, conflicts=#{run.conflict_count}"
    puts "Lectures: new=#{run.new_lectures_count}"
    puts "Offerings: new=#{run.new_offerings_count}, updated=#{run.updated_offerings_count}, unchanged=#{run.unchanged_offerings_count}, missing=#{run.missing_offerings_count}"
    puts "Run `bundle exec rake lectures:syllabus_report IMPORT_RUN_ID=#{run.id}` to inspect details."
    puts "No Lecture, Offering, Review, Bookmark, or TimetableEntry was changed."
  rescue ArgumentError, Syllabus::ImportAnalyzer::Error => e
    warn e.message
    exit 1
  end

  desc 'Analyze a syllabus CSV and persist its diff without changing domain data'
  task syllabus_analyze: :environment do
    result = Syllabus::ImportAnalyzer.new(csv_path: ENV['CSV_PATH'], year: ENV['YEAR']).call
    run = result.run
    puts "Import run: #{run.id}"
    puts "Year: #{run.year}, status=#{run.status}, source=#{run.source_type}"
    puts "Rows: total=#{run.total_rows}, valid=#{run.valid_rows}, errors=#{run.error_count}, conflicts=#{run.conflict_count}"
    puts "Lectures: new=#{run.new_lectures_count}"
    puts "Offerings: new=#{run.new_offerings_count}, updated=#{run.updated_offerings_count}, unchanged=#{run.unchanged_offerings_count}, missing=#{run.missing_offerings_count}"
    puts run.error_summary if run.error_summary.present?
  rescue ArgumentError, Syllabus::ImportAnalyzer::Error => e
    warn e.message
    exit 1
  end

  desc 'Apply an analyzed syllabus import run'
  task syllabus_apply: :environment do
    result = Syllabus::ImportApplier.new(
      import_run_id: ENV.fetch('IMPORT_RUN_ID'),
      confirm: ENV['CONFIRM'] == 'true',
      confirm_missing: ENV['CONFIRM_MISSING'] == 'true'
    ).call
    puts "Import run #{result.run.id}: status=#{result.run.status}"
    puts "Rows applied: #{result.applied_rows}"
    puts "Missing rows skipped: #{result.skipped_missing_rows}"
    if result.run.missing_completion_pending?
      puts "未掲載差分を確認後、同じIMPORT_RUN_IDにCONFIRM_MISSING=trueを付けて再実行してください。"
    end
  rescue KeyError, ActiveRecord::RecordNotFound, Syllabus::ImportApplier::Error => e
    warn e.message
    exit 1
  end

  desc 'Rollback the latest applied syllabus run for its year'
  task syllabus_rollback: :environment do
    result = Syllabus::ImportRollback.new(
      import_run_id: ENV.fetch('IMPORT_RUN_ID'),
      confirm: ENV['CONFIRM'] == 'true'
    ).call
    puts "Import run #{result.run.id} rolled back."
    puts "Rows restored: #{result.restored_rows}"
  rescue KeyError, ActiveRecord::RecordNotFound, Syllabus::ImportRollback::Error => e
    warn e.message
    exit 1
  end

  desc 'Show summary and row-level issues for a syllabus import run'
  task syllabus_report: :environment do
    run = SyllabusImportRun.find(ENV.fetch('IMPORT_RUN_ID'))
    puts "Run #{run.id}: year=#{run.year}, status=#{run.status}, source=#{run.source_file_name}"
    puts "Rows: total=#{run.total_rows}, valid=#{run.valid_rows}, errors=#{run.error_count}, conflicts=#{run.conflict_count}"
    puts "Lectures: new=#{run.new_lectures_count}"
    puts "Offerings: new=#{run.new_offerings_count}, updated=#{run.updated_offerings_count}, unchanged=#{run.unchanged_offerings_count}, missing=#{run.missing_offerings_count}"
    puts "Faculty counts: #{run.faculty_counts.to_json}"
    puts run.error_summary if run.error_summary.present?
    run.syllabus_import_rows.where(action: %w[conflict error]).order(:sequence_number).find_each do |row|
      puts "sequence=#{row.sequence_number}, source_row=#{row.source_row_number || '-'}, action=#{row.action}, code=#{row.registration_code}, messages=#{Array(row.messages).join(' / ')}"
    end
  rescue KeyError, ActiveRecord::RecordNotFound => e
    warn e.message
    exit 1
  end

  desc 'Audit syllabus-related existing data without changing it'
  task syllabus_audit: :environment do
    result = Syllabus::DatabaseAudit.new.call
    puts JSON.pretty_generate(result.to_h)
  end

  desc 'Backfill additive syllabus columns after a clean audit'
  task syllabus_backfill: :environment do
    result = Syllabus::LegacyDataBackfill.new(confirm: ENV['CONFIRM'] == 'true').call
    puts "Backfill completed: lectures=#{result.lectures_updated}, reviews=#{result.reviews_updated}, offerings=#{result.offerings_updated}"
  rescue Syllabus::LegacyDataBackfill::Error => e
    warn e.message
    exit 1
  end

  desc 'Show lecture counts before or after an import'
  task count: :environment do
    if ENV['FACULTY'].present?
      puts "#{ENV['FACULTY']}: #{Lecture.where(faculty: ENV['FACULTY']).count}"
    else
      puts "Total lectures: #{Lecture.count}"
      Lecture.group(:faculty).count.sort_by { |faculty, _| faculty.to_s }.each do |faculty, count|
        label = faculty.presence || '(blank faculty)'
        puts "#{label}: #{count}"
      end
    end
  end

  desc 'Show yearly lecture offering and slot counts'
  task offerings_count: :environment do
    LectureOffering.group(:year).order(:year).count.each do |year, offering_count|
      offering_ids = LectureOffering.where(year: year).select(:id)
      slot_count = OfferingSlot.where(lecture_offering_id: offering_ids).count
      without_slots_count = LectureOffering.where(year: year)
                                           .where.not(id: OfferingSlot.select(:lecture_offering_id))
                                           .count
      status_counts = LectureOffering.where(year:).group(:source_status).count
      puts "#{year}: offerings=#{offering_count}, active=#{status_counts['active'].to_i}, missing=#{status_counts['missing'].to_i}, slots=#{slot_count}, offerings_without_slots=#{without_slots_count}"
    end
  end
end
