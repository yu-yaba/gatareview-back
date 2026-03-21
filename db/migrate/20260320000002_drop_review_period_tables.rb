class DropReviewPeriodTables < ActiveRecord::Migration[7.0]
  def up
    drop_table :user_review_period_counts, if_exists: true
    drop_table :review_periods, if_exists: true
  end

  def down
    create_table :review_periods do |t|
      t.string :period_name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.boolean :is_active, default: false, null: false

      t.timestamps
    end

    add_index :review_periods, :period_name, unique: true
    add_index :review_periods, :is_active
    add_index :review_periods, %i[start_date end_date]

    create_table :user_review_period_counts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :review_period, null: false, foreign_key: true
      t.integer :reviews_count, default: 0, null: false

      t.timestamps
    end

    add_index :user_review_period_counts, %i[user_id review_period_id], unique: true,
              name: 'index_user_period_counts_unique'
  end
end
