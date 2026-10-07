class HardenSyllabusImportManifests < ActiveRecord::Migration[7.0]
  UNIQUE_NORMALIZED_KEY_INDEX = 'index_lectures_on_normalized_key_unique'
  LEGACY_NORMALIZED_KEY_INDEX = 'index_lectures_on_normalized_key'

  def up
    add_manifest_columns
    add_normalized_key_unique_index
  end

  def down
    restore_legacy_normalized_key_index
    remove_index :lectures, name: UNIQUE_NORMALIZED_KEY_INDEX if index_named?(:lectures, UNIQUE_NORMALIZED_KEY_INDEX)

    remove_import_result_reference(:applied_offering, :lecture_offerings)
    remove_import_result_reference(:applied_lecture, :lectures)
    remove_column :syllabus_import_runs, :applied_result_sha256 if column_exists?(:syllabus_import_runs, :applied_result_sha256)
    remove_column :syllabus_import_runs, :staged_payload_version if column_exists?(:syllabus_import_runs, :staged_payload_version)
  end

  private

  def add_manifest_columns
    unless column_exists?(:syllabus_import_runs, :staged_payload_version)
      add_column :syllabus_import_runs, :staged_payload_version, :integer, null: false, default: 1
    end
    unless column_exists?(:syllabus_import_runs, :applied_result_sha256)
      add_column :syllabus_import_runs, :applied_result_sha256, :string, limit: 64
    end
    add_import_result_reference(:applied_lecture, :lectures)
    add_import_result_reference(:applied_offering, :lecture_offerings, on_delete: :nullify)
  end

  def add_normalized_key_unique_index
    duplicate = select_one(<<~SQL.squish)
      SELECT normalized_key, COUNT(*) AS duplicate_count
      FROM lectures
      WHERE normalized_key IS NOT NULL
      GROUP BY normalized_key
      HAVING COUNT(*) > 1
      LIMIT 1
    SQL
    if duplicate
      raise ActiveRecord::MigrationError,
            "lectures.normalized_key に重複があるためunique indexを追加できません。" \
            "syllabus_auditで解消してください: normalized_key=#{duplicate['normalized_key']}, " \
            "count=#{duplicate['duplicate_count']}"
    end

    unless index_named?(:lectures, UNIQUE_NORMALIZED_KEY_INDEX)
      add_index :lectures, :normalized_key, unique: true, name: UNIQUE_NORMALIZED_KEY_INDEX
    end
    remove_index :lectures, name: LEGACY_NORMALIZED_KEY_INDEX if index_named?(:lectures, LEGACY_NORMALIZED_KEY_INDEX)
  end

  def restore_legacy_normalized_key_index
    return if index_named?(:lectures, LEGACY_NORMALIZED_KEY_INDEX)

    add_index :lectures, :normalized_key, name: LEGACY_NORMALIZED_KEY_INDEX
  end

  def add_import_result_reference(name, target_table, on_delete: nil)
    column = "#{name}_id"
    index_name = "index_syllabus_import_rows_on_#{column}"
    add_column :syllabus_import_rows, column, :bigint unless column_exists?(:syllabus_import_rows, column)
    add_index :syllabus_import_rows, column, name: index_name unless index_named?(:syllabus_import_rows, index_name)
    return if foreign_key_exists?(:syllabus_import_rows, target_table, column: column)

    options = { column: column }
    options[:on_delete] = on_delete if on_delete
    add_foreign_key :syllabus_import_rows, target_table, **options
  end

  def remove_import_result_reference(name, target_table)
    column = "#{name}_id"
    return unless column_exists?(:syllabus_import_rows, column)

    remove_foreign_key :syllabus_import_rows, target_table, column: column if foreign_key_exists?(:syllabus_import_rows, target_table, column: column)
    remove_index :syllabus_import_rows, name: "index_syllabus_import_rows_on_#{column}" if index_named?(:syllabus_import_rows, "index_syllabus_import_rows_on_#{column}")
    remove_column :syllabus_import_rows, column
  end

  def index_named?(table, name)
    connection.indexes(table).any? { |index| index.name == name }
  end
end
