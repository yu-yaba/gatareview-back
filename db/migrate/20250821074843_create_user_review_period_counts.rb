class CreateUserReviewPeriodCounts < ActiveRecord::Migration[7.0]
  def change
    create_table :user_review_period_counts do |t|
      t.references :user, null: false, foreign_key: true, comment: 'ユーザーID'
      t.references :review_period, null: false, foreign_key: true, comment: 'レビュー期間ID'
      t.integer :reviews_count, default: 0, null: false, comment: '期間内のレビュー投稿数'

      t.timestamps
    end

    add_index :user_review_period_counts, [:user_id, :review_period_id], unique: true, name: 'index_user_period_counts_unique'
  end
end
