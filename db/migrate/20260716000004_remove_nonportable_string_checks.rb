class RemoveNonportableStringChecks < ActiveRecord::Migration[7.0]
  CHECKS = {
    syllabus_import_runs: ['syllabus_import_runs_status'],
    lecture_offerings: %w[lecture_offerings_schedule_kind lecture_offerings_source_status]
  }.freeze

  def up
    CHECKS.each do |table, names|
      names.each do |name|
        remove_check_constraint(table, name:) if check_exists?(table, name)
      end
    end
  end

  def down
    # Rails 7.0のMySQL schema dumperが文字列CHECKを再現できないため復元しない。
    # 許容値はモデルvalidationで保護する。
  end

  private

  def check_exists?(table, name)
    quoted_table = connection.quote(table.to_s)
    quoted_name = connection.quote(name)
    connection.select_value(<<~SQL.squish).present?
      SELECT 1
      FROM information_schema.TABLE_CONSTRAINTS
      WHERE CONSTRAINT_SCHEMA = DATABASE()
        AND TABLE_NAME = #{quoted_table}
        AND CONSTRAINT_NAME = #{quoted_name}
        AND CONSTRAINT_TYPE = 'CHECK'
      LIMIT 1
    SQL
  end
end
