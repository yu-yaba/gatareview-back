class CreateReviews < ActiveRecord::Migration[7.0]
  def change
    create_table :reviews do |t|
      t.float :rating
      t.text :content
      t.string :lecture_id
      t.string :textbook
      t.string :attendance
      t.string :grading_type
      t.string :content_difficulty
      t.string :content_quality
      t.string :period_year
      t.string :period_term

      t.timestamps
    end
  end
end
