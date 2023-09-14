class AddAvgRatingToLectures < ActiveRecord::Migration[7.0]
  def change
    add_column :lectures, :avg_rating, :float
  end
end
