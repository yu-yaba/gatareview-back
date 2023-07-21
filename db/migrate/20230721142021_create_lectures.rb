class CreateLectures < ActiveRecord::Migration[7.0]
  def change
    create_table :lectures do |t|
      t.string :title
      t.string :lecturer
      t.string :faculty

      t.timestamps
    end
  end
end
