class CreateReviewPeriods < ActiveRecord::Migration[7.0]
  def change
    create_table :review_periods do |t|
      t.string :period_name, null: false, comment: '期間名 (例: 2025-spring)'
      t.datetime :start_date, null: false, comment: '期間開始日'
      t.datetime :end_date, null: false, comment: '期間終了日'
      t.boolean :is_active, default: false, null: false, comment: '現在有効な期間かを示すフラグ'

      t.timestamps
    end

    add_index :review_periods, :period_name, unique: true
    add_index :review_periods, :is_active
    add_index :review_periods, [:start_date, :end_date]
  end
end
