class AddUserIdToReviews < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:reviews, :user_id)
      add_column :reviews, :user_id, :bigint
    else
      # 既存のuser_idカラムの型をbigintに変更
      change_column :reviews, :user_id, :bigint
    end
    
    add_index :reviews, :user_id unless index_exists?(:reviews, :user_id)
    add_foreign_key :reviews, :users unless foreign_key_exists?(:reviews, :users)
  end
end
