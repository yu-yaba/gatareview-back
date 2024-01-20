class RemoveAvgRatingFromLectures < ActiveRecord::Migration[6.0]
  def change
    remove_column :lectures, :avg_rating, :float
  end
end
