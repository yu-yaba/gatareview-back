class AddAvgRatingToLectures < ActiveRecord::Migration[6.0]
  def change
    add_column :lectures, :avg_rating, :float, default: 0.0
  end
end
