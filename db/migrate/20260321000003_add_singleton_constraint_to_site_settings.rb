class AddSingletonConstraintToSiteSettings < ActiveRecord::Migration[7.0]
  INDEX_NAME = 'index_site_settings_on_singleton_guard'

  def up
    site_settings_count = select_value('SELECT COUNT(*) FROM site_settings').to_i

    raise 'site_settings must have at most one row before adding singleton constraint' if site_settings_count > 1

    execute('UPDATE site_settings SET id = 1 WHERE id <> 1') if site_settings_count == 1

    add_column :site_settings, :singleton_guard, :integer, null: false, default: 1
    add_index :site_settings, :singleton_guard, unique: true, name: INDEX_NAME
  end

  def down
    remove_index :site_settings, name: INDEX_NAME
    remove_column :site_settings, :singleton_guard
  end
end
