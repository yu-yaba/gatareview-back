class CreateBookmarks < ActiveRecord::Migration[7.0]
  def change
    create_table :bookmarks do |t|
      t.references :user, foreign_key: true
      t.references :lecture, foreign_key: true

      t.timestamps
    end
    
    # ユニーク制約を追加（一人のユーザーが同じ授業を複数回ブックマークできない）
    add_index :bookmarks, [:user_id, :lecture_id], unique: true
  end
end
