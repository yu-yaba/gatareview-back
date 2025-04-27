# frozen_string_literal: true

class AddUniqueIndexToLectures < ActiveRecord::Migration[7.0]
  # lectures テーブルの title, lecturer, faculty カラムに複合ユニークインデックスを追加。
  # activerecord-import の ignore: true オプションが効率的に動作するために必要。
  def change
    add_index :lectures,
              [:title, :lecturer, :faculty],
              unique: true,
              name: 'index_lectures_on_title_lecturer_faculty'
  end
end
