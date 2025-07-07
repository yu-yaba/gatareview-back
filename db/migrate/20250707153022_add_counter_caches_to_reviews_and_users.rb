class AddCounterCachesToReviewsAndUsers < ActiveRecord::Migration[7.0]
  def change
    # reviews テーブルに thanks_count カラムを追加
    add_column :reviews, :thanks_count, :integer, default: 0, null: false
    
    # users テーブルに reviews_count カラムを追加
    add_column :users, :reviews_count, :integer, default: 0, null: false
    
    # 既存データのカウンターキャッシュを更新
    reversible do |dir|
      dir.up do
        # reviews の thanks_count を更新
        execute <<-SQL
          UPDATE reviews 
          SET thanks_count = (
            SELECT COUNT(*) 
            FROM thanks 
            WHERE thanks.review_id = reviews.id
          )
        SQL
        
        # users の reviews_count を更新
        execute <<-SQL
          UPDATE users 
          SET reviews_count = (
            SELECT COUNT(*) 
            FROM reviews 
            WHERE reviews.user_id = users.id
          )
        SQL
      end
    end
  end
end
