class ExtendSyllabusEntities < ActiveRecord::Migration[7.0]
  def change
    extend_lectures
    extend_offerings
    extend_reviews
    extend_timetable_entries
  end

  private

  def extend_lectures
    add_column :lectures, :normalized_key, :string, limit: 64 unless column_exists?(:lectures, :normalized_key)
    add_reference :lectures, :merged_into_lecture, null: true, foreign_key: { to_table: :lectures } unless column_exists?(:lectures, :merged_into_lecture_id)
    add_column :lectures, :merged_at, :datetime unless column_exists?(:lectures, :merged_at)
    add_index :lectures, :normalized_key unless index_exists?(:lectures, :normalized_key)
  end

  def extend_offerings
    add_reference :lecture_offerings, :syllabus_organization, null: true, foreign_key: true unless column_exists?(:lecture_offerings, :syllabus_organization_id)
    add_column :lecture_offerings, :source_title, :string unless column_exists?(:lecture_offerings, :source_title)
    add_column :lecture_offerings, :source_lecturer, :string unless column_exists?(:lecture_offerings, :source_lecturer)
    add_column :lecture_offerings, :source_faculty, :string unless column_exists?(:lecture_offerings, :source_faculty)
    add_column :lecture_offerings, :raw_day_periods, :string unless column_exists?(:lecture_offerings, :raw_day_periods)
    add_column :lecture_offerings, :schedule_kind, :string, null: false, default: 'unknown' unless column_exists?(:lecture_offerings, :schedule_kind)
    add_column :lecture_offerings, :source_status, :string, null: false, default: 'active' unless column_exists?(:lecture_offerings, :source_status)
    add_column :lecture_offerings, :source_checksum, :string, limit: 64 unless column_exists?(:lecture_offerings, :source_checksum)
    add_import_run_reference(:first_seen_import_run)
    add_import_run_reference(:last_seen_import_run)
    add_import_run_reference(:missing_since_import_run)

    add_index :lecture_offerings, %i[year source_status] unless index_exists?(:lecture_offerings, %i[year source_status])
    add_index :lecture_offerings, :source_checksum unless index_exists?(:lecture_offerings, :source_checksum)
  end

  def add_import_run_reference(name)
    return if column_exists?(:lecture_offerings, "#{name}_id")

    add_reference :lecture_offerings, name, null: true, foreign_key: { to_table: :syllabus_import_runs }
  end

  def extend_reviews
    add_column :reviews, :lecture_id_bigint, :bigint unless column_exists?(:reviews, :lecture_id_bigint)
    add_reference :reviews, :lecture_offering, null: true, foreign_key: true unless column_exists?(:reviews, :lecture_offering_id)
    add_column :reviews, :academic_year, :integer unless column_exists?(:reviews, :academic_year)
    add_column :reviews, :term_code, :string unless column_exists?(:reviews, :term_code)
    add_index :reviews, :lecture_id_bigint unless index_exists?(:reviews, :lecture_id_bigint)
    add_foreign_key :reviews, :lectures, column: :lecture_id_bigint unless foreign_key_exists?(:reviews, :lectures, column: :lecture_id_bigint)
  end

  def extend_timetable_entries
    return unless table_exists?(:timetable_entries)
    return if column_exists?(:timetable_entries, :lecture_offering_id)

    add_reference :timetable_entries, :lecture_offering, null: true, foreign_key: true
  end
end
