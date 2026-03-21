class CreateDefaultSiteSetting < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      INSERT INTO site_settings (
        id,
        lecture_review_restriction_enabled,
        last_updated_by_user_id,
        created_at,
        updated_at,
        singleton_guard
      )
      SELECT
        1,
        FALSE,
        NULL,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        1
      WHERE NOT EXISTS (
        SELECT 1
        FROM site_settings
        WHERE id = 1
      )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'default site_setting row should not be removed automatically'
  end
end
