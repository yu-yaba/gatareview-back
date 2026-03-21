class CreateSiteSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :site_settings do |t|
      t.boolean :lecture_review_restriction_enabled, null: false, default: false
      t.references :last_updated_by_user, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end
  end
end
