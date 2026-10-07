class CreateTimetableEntries < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:timetable_entries)
      create_table :timetable_entries do |t|
        t.references :user, null: false, foreign_key: true
        t.references :lecture, null: false, foreign_key: true
        t.integer :year, null: false
        t.integer :term, null: false
        t.integer :day
        t.integer :period

        t.timestamps
      end
    end

    unless index_exists?(:timetable_entries, %i[user_id year term day period], unique: true)
      add_index :timetable_entries, %i[user_id year term day period], unique: true, name: 'index_timetable_entries_on_user_and_slot'
    end

    add_index :timetable_entries, %i[user_id year] unless index_exists?(:timetable_entries, %i[user_id year])
  end
end
