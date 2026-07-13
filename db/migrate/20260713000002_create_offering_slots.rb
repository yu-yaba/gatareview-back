class CreateOfferingSlots < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:offering_slots)
      create_table :offering_slots do |t|
        t.references :lecture_offering, null: false, foreign_key: true
        t.integer :day, null: false
        t.integer :period, null: false

        t.timestamps
      end
    end

    # 同一開講の同一コマは1件（「月2, 木2」は2レコードになる）
    unless index_exists?(:offering_slots, %i[lecture_offering_id day period], unique: true)
      add_index :offering_slots, %i[lecture_offering_id day period], unique: true, name: 'index_offering_slots_on_offering_and_slot'
    end

    # 曜限検索用
    unless index_exists?(:offering_slots, %i[day period])
      add_index :offering_slots, %i[day period]
    end
  end
end
