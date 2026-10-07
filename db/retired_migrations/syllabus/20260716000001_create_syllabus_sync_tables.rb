class CreateSyllabusSyncTables < ActiveRecord::Migration[7.0]
  ORGANIZATIONS = [
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

  def up
    create_import_runs
    create_organizations
    create_import_rows
    create_lecture_aliases
    create_offering_details
    seed_organizations
  end

  def down
    drop_table :lecture_offering_details, if_exists: true
    drop_table :lecture_aliases, if_exists: true
    drop_table :syllabus_import_rows, if_exists: true
    drop_table :syllabus_organizations, if_exists: true
    drop_table :syllabus_import_runs, if_exists: true
  end

  private

  def create_import_runs
    return if table_exists?(:syllabus_import_runs)

    create_table :syllabus_import_runs do |t|
      t.integer :year, null: false
      t.string :source_type, null: false
      t.string :source_file_name, null: false
      t.bigint :source_size_bytes, null: false
      t.string :source_sha256, limit: 64, null: false
      t.string :staged_sha256, limit: 64
      t.string :status, null: false, default: 'analyzing'
      t.integer :total_rows, null: false, default: 0
      t.integer :valid_rows, null: false, default: 0
      t.integer :new_lectures_count, null: false, default: 0
      t.integer :new_offerings_count, null: false, default: 0
      t.integer :updated_offerings_count, null: false, default: 0
      t.integer :unchanged_offerings_count, null: false, default: 0
      t.integer :missing_offerings_count, null: false, default: 0
      t.integer :conflict_count, null: false, default: 0
      t.integer :warning_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.json :faculty_counts
      t.text :error_summary
      t.datetime :started_at, null: false
      t.datetime :analyzed_at
      t.datetime :applied_at
      t.datetime :rolled_back_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :syllabus_import_runs, %i[year status]
    add_index :syllabus_import_runs, :source_sha256
  end

  def create_organizations
    return if table_exists?(:syllabus_organizations)

    create_table :syllabus_organizations do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :faculty_label, null: false
      t.boolean :enabled_for_import, null: false, default: true
      t.integer :valid_from_year, null: false
      t.integer :valid_until_year

      t.timestamps
    end

    add_index :syllabus_organizations, %i[code valid_from_year], unique: true, name: 'index_syllabus_orgs_on_code_and_start_year'
    add_index :syllabus_organizations, %i[enabled_for_import valid_from_year valid_until_year], name: 'index_syllabus_orgs_on_import_and_validity'
  end

  def create_import_rows
    return if table_exists?(:syllabus_import_rows)

    create_table :syllabus_import_rows do |t|
      t.references :syllabus_import_run, null: false, foreign_key: true
      t.integer :sequence_number, null: false
      t.integer :source_row_number
      t.integer :year
      t.string :registration_code
      t.string :source_title
      t.string :source_lecturer
      t.string :source_faculty
      t.string :normalized_key, limit: 64
      t.string :shozoku_code
      t.string :semester_label
      t.string :term_label
      t.string :term_code
      t.string :raw_day_periods
      t.string :schedule_kind
      t.string :action, null: false
      t.references :matched_lecture, null: true, foreign_key: { to_table: :lectures }
      t.references :matched_offering, null: true, foreign_key: { to_table: :lecture_offerings }
      t.json :messages
      t.json :before_values
      t.json :after_values
      t.string :row_checksum, limit: 64, null: false

      t.timestamps
    end

    add_index :syllabus_import_rows, %i[syllabus_import_run_id sequence_number], unique: true, name: 'index_syllabus_rows_on_run_and_sequence'
    add_index :syllabus_import_rows, %i[syllabus_import_run_id action], name: 'index_syllabus_rows_on_run_and_action'
    add_index :syllabus_import_rows, %i[year registration_code]
    add_index :syllabus_import_rows, :normalized_key
  end

  def create_lecture_aliases
    return if table_exists?(:lecture_aliases)

    create_table :lecture_aliases do |t|
      t.references :lecture, null: false, foreign_key: true
      t.string :title, null: false
      t.string :lecturer, null: false
      t.string :faculty, null: false
      t.string :normalized_key, limit: 64, null: false
      t.boolean :confirmed, null: false, default: false
      t.string :match_method, null: false, default: 'manual'
      t.references :created_from_import_run, null: true, foreign_key: { to_table: :syllabus_import_runs }, index: { name: 'index_lecture_aliases_on_import_run' }

      t.timestamps
    end

    add_index :lecture_aliases, :normalized_key, unique: true
  end

  def create_offering_details
    return if table_exists?(:lecture_offering_details)

    create_table :lecture_offering_details do |t|
      t.references :lecture_offering, null: false, foreign_key: true, index: { unique: true, name: 'index_offering_details_on_offering' }
      t.decimal :credits, precision: 4, scale: 1
      t.json :target_years
      t.string :campus
      t.string :language
      t.string :delivery_method
      t.string :subject_category
      t.datetime :source_updated_at
      t.datetime :fetched_at
      t.string :source_checksum, limit: 64

      t.timestamps
    end
  end

  def seed_organizations
    now = Time.current
    rows = ORGANIZATIONS.map do |organization|
      organization.merge(valid_from_year: 2026, enabled_for_import: true, created_at: now, updated_at: now)
    end

    Class.new(ActiveRecord::Base) do
      self.table_name = 'syllabus_organizations'
    end.insert_all(rows)
  end
end
