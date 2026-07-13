class CreateLectureOfferings < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:lecture_offerings)
      create_table :lecture_offerings do |t|
        t.references :lecture, null: false, foreign_key: true
        t.integer :year, null: false
        t.string :registration_code, null: false
        t.string :shozoku_code, null: false
        t.string :semester_label
        t.string :term_label
        t.string :term_code

        t.timestamps
      end
    end

    # 開講番号は年度内で一意（年度をまたぐと再利用されうる）
    unless index_exists?(:lecture_offerings, %i[year registration_code], unique: true)
      add_index :lecture_offerings, %i[year registration_code], unique: true
    end

    unless index_exists?(:lecture_offerings, %i[year term_code])
      add_index :lecture_offerings, %i[year term_code]
    end
  end
end
