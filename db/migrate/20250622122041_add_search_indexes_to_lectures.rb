class AddSearchIndexesToLectures < ActiveRecord::Migration[7.0]
  def change
    add_index :lectures, :title
    add_index :lectures, :lecturer
    add_index :lectures, [:title, :lecturer], name: 'index_lectures_on_title_and_lecturer'
    add_index :reviews, :lecture_id unless index_exists?(:reviews, :lecture_id)
  end
end
