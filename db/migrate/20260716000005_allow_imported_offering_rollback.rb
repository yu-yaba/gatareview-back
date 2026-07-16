class AllowImportedOfferingRollback < ActiveRecord::Migration[7.0]
  def up
    remove_foreign_key :syllabus_import_rows, column: :matched_offering_id
    add_foreign_key :syllabus_import_rows, :lecture_offerings,
                    column: :matched_offering_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :syllabus_import_rows, column: :matched_offering_id
    add_foreign_key :syllabus_import_rows, :lecture_offerings,
                    column: :matched_offering_id
  end
end
