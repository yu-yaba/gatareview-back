class CreateThanks < ActiveRecord::Migration[7.0]
  def change
    create_table :thanks do |t|
      t.references :user, foreign_key: true
      t.references :review, foreign_key: true

      t.timestamps
    end
    
    # ユニーク制約を追加（一人のユーザーが同じレビューに複数回ありがとうできない）
    add_index :thanks, [:user_id, :review_id], unique: true
  end
end
