class PreserveAppliedOfferingSnapshotId < ActiveRecord::Migration[7.0]
  def up
    return unless foreign_key_exists?(:syllabus_import_rows, :lecture_offerings, column: :applied_offering_id)

    # applied_offering_idはrollback後にも残す監査snapshotであり、
    # 削除済みOfferingへのIDを保持できるよう意図的にFKを外す。
    remove_foreign_key :syllabus_import_rows, :lecture_offerings, column: :applied_offering_id
  end

  def down
    return if foreign_key_exists?(:syllabus_import_rows, :lecture_offerings, column: :applied_offering_id)

    orphan_exists = select_value(<<~SQL.squish)
      SELECT 1
      FROM syllabus_import_rows AS import_rows
      LEFT JOIN lecture_offerings AS offerings
        ON offerings.id = import_rows.applied_offering_id
      WHERE import_rows.applied_offering_id IS NOT NULL
        AND offerings.id IS NULL
      LIMIT 1
    SQL
    if orphan_exists
      raise ActiveRecord::IrreversibleMigration,
            'rollback済みOfferingの監査snapshotがあるため、applied_offering_idのFKを復元できません'
    end

    add_foreign_key :syllabus_import_rows, :lecture_offerings,
                    column: :applied_offering_id, on_delete: :nullify
  end
end
