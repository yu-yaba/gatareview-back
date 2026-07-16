# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_07_16_000005) do
  create_table "bookmarks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "lecture_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lecture_id"], name: "index_bookmarks_on_lecture_id"
    t.index ["user_id", "lecture_id"], name: "index_bookmarks_on_user_id_and_lecture_id", unique: true
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "lecture_aliases", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "lecture_id", null: false
    t.string "title", null: false
    t.string "lecturer", null: false
    t.string "faculty", null: false
    t.string "normalized_key", limit: 64, null: false
    t.boolean "confirmed", default: false, null: false
    t.string "match_method", default: "manual", null: false
    t.bigint "created_from_import_run_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_from_import_run_id"], name: "index_lecture_aliases_on_import_run"
    t.index ["lecture_id"], name: "index_lecture_aliases_on_lecture_id"
    t.index ["normalized_key"], name: "index_lecture_aliases_on_normalized_key", unique: true
  end

  create_table "lecture_offering_details", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "lecture_offering_id", null: false
    t.decimal "credits", precision: 4, scale: 1
    t.json "target_years"
    t.string "campus"
    t.string "language"
    t.string "delivery_method"
    t.string "subject_category"
    t.datetime "source_updated_at"
    t.datetime "fetched_at"
    t.string "source_checksum", limit: 64
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lecture_offering_id"], name: "index_offering_details_on_offering", unique: true
  end

  create_table "lecture_offerings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "lecture_id", null: false
    t.integer "year", null: false
    t.string "registration_code", null: false
    t.string "shozoku_code", null: false
    t.string "semester_label"
    t.string "term_label"
    t.string "term_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "syllabus_organization_id"
    t.string "source_title"
    t.string "source_lecturer"
    t.string "source_faculty"
    t.string "raw_day_periods"
    t.string "schedule_kind", default: "unknown", null: false
    t.string "source_status", default: "active", null: false
    t.string "source_checksum", limit: 64
    t.bigint "first_seen_import_run_id"
    t.bigint "last_seen_import_run_id"
    t.bigint "missing_since_import_run_id"
    t.index ["first_seen_import_run_id"], name: "index_lecture_offerings_on_first_seen_import_run_id"
    t.index ["last_seen_import_run_id"], name: "index_lecture_offerings_on_last_seen_import_run_id"
    t.index ["lecture_id"], name: "index_lecture_offerings_on_lecture_id"
    t.index ["missing_since_import_run_id"], name: "index_lecture_offerings_on_missing_since_import_run_id"
    t.index ["source_checksum"], name: "index_lecture_offerings_on_source_checksum"
    t.index ["syllabus_organization_id"], name: "index_lecture_offerings_on_syllabus_organization_id"
    t.index ["year", "registration_code"], name: "index_lecture_offerings_on_year_and_registration_code", unique: true
    t.index ["year", "source_status"], name: "index_lecture_offerings_on_year_and_source_status"
    t.index ["year", "term_code"], name: "index_lecture_offerings_on_year_and_term_code"
  end

  create_table "lectures", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "title"
    t.string "lecturer"
    t.string "faculty"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source_name"
    t.string "source_external_id"
    t.string "normalized_key", limit: 64
    t.bigint "merged_into_lecture_id"
    t.datetime "merged_at"
    t.index ["lecturer"], name: "index_lectures_on_lecturer"
    t.index ["merged_into_lecture_id"], name: "index_lectures_on_merged_into_lecture_id"
    t.index ["normalized_key"], name: "index_lectures_on_normalized_key"
    t.index ["source_name", "source_external_id"], name: "index_lectures_on_source_name_and_source_external_id", unique: true
    t.index ["title", "lecturer", "faculty"], name: "index_lectures_on_title_lecturer_faculty", unique: true
    t.index ["title", "lecturer"], name: "index_lectures_on_title_and_lecturer"
    t.index ["title"], name: "index_lectures_on_title"
  end

  create_table "offering_slots", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "lecture_offering_id", null: false
    t.integer "day", null: false
    t.integer "period", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day", "period"], name: "index_offering_slots_on_day_and_period"
    t.index ["lecture_offering_id", "day", "period"], name: "index_offering_slots_on_offering_and_slot", unique: true
    t.index ["lecture_offering_id"], name: "index_offering_slots_on_lecture_offering_id"
    t.check_constraint "`day` between 1 and 7", name: "offering_slots_day_range"
    t.check_constraint "`period` between 1 and 7", name: "offering_slots_period_range"
  end

  create_table "reviews", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.float "rating"
    t.text "content"
    t.string "lecture_id"
    t.string "textbook"
    t.string "attendance"
    t.string "grading_type"
    t.string "content_difficulty"
    t.string "content_quality"
    t.string "period_year"
    t.string "period_term"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.integer "thanks_count", default: 0, null: false
    t.string "source_name"
    t.string "source_external_id"
    t.bigint "lecture_id_bigint"
    t.bigint "lecture_offering_id"
    t.integer "academic_year"
    t.string "term_code"
    t.index ["lecture_id", "content_difficulty"], name: "index_reviews_on_lecture_id_and_content_difficulty"
    t.index ["lecture_id", "content_quality"], name: "index_reviews_on_lecture_id_and_content_quality"
    t.index ["lecture_id", "period_year"], name: "index_reviews_on_lecture_id_and_period_year"
    t.index ["lecture_id"], name: "index_reviews_on_lecture_id"
    t.index ["lecture_id_bigint"], name: "index_reviews_on_lecture_id_bigint"
    t.index ["lecture_offering_id"], name: "index_reviews_on_lecture_offering_id"
    t.index ["source_name", "source_external_id"], name: "index_reviews_on_source_name_and_source_external_id", unique: true
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "site_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.boolean "lecture_review_restriction_enabled", default: false, null: false
    t.bigint "last_updated_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "singleton_guard", default: 1, null: false
    t.index ["last_updated_by_user_id"], name: "index_site_settings_on_last_updated_by_user_id"
    t.index ["singleton_guard"], name: "index_site_settings_on_singleton_guard", unique: true
  end

  create_table "syllabus_import_rows", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "syllabus_import_run_id", null: false
    t.integer "sequence_number", null: false
    t.integer "source_row_number"
    t.integer "year"
    t.string "registration_code"
    t.string "source_title"
    t.string "source_lecturer"
    t.string "source_faculty"
    t.string "normalized_key", limit: 64
    t.string "shozoku_code"
    t.string "semester_label"
    t.string "term_label"
    t.string "term_code"
    t.string "raw_day_periods"
    t.string "schedule_kind"
    t.string "action", null: false
    t.bigint "matched_lecture_id"
    t.bigint "matched_offering_id"
    t.json "messages"
    t.json "before_values"
    t.json "after_values"
    t.string "row_checksum", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["matched_lecture_id"], name: "index_syllabus_import_rows_on_matched_lecture_id"
    t.index ["matched_offering_id"], name: "index_syllabus_import_rows_on_matched_offering_id"
    t.index ["normalized_key"], name: "index_syllabus_import_rows_on_normalized_key"
    t.index ["syllabus_import_run_id", "action"], name: "index_syllabus_rows_on_run_and_action"
    t.index ["syllabus_import_run_id", "sequence_number"], name: "index_syllabus_rows_on_run_and_sequence", unique: true
    t.index ["syllabus_import_run_id"], name: "index_syllabus_import_rows_on_syllabus_import_run_id"
    t.index ["year", "registration_code"], name: "index_syllabus_import_rows_on_year_and_registration_code"
  end

  create_table "syllabus_import_runs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "year", null: false
    t.string "source_type", null: false
    t.string "source_file_name", null: false
    t.bigint "source_size_bytes", null: false
    t.string "source_sha256", limit: 64, null: false
    t.string "staged_sha256", limit: 64
    t.string "status", default: "analyzing", null: false
    t.integer "total_rows", default: 0, null: false
    t.integer "valid_rows", default: 0, null: false
    t.integer "new_lectures_count", default: 0, null: false
    t.integer "new_offerings_count", default: 0, null: false
    t.integer "updated_offerings_count", default: 0, null: false
    t.integer "unchanged_offerings_count", default: 0, null: false
    t.integer "missing_offerings_count", default: 0, null: false
    t.integer "conflict_count", default: 0, null: false
    t.integer "warning_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.json "faculty_counts"
    t.text "error_summary"
    t.datetime "started_at", null: false
    t.datetime "analyzed_at"
    t.datetime "applied_at"
    t.datetime "rolled_back_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_sha256"], name: "index_syllabus_import_runs_on_source_sha256"
    t.index ["year", "status"], name: "index_syllabus_import_runs_on_year_and_status"
  end

  create_table "syllabus_organizations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.string "faculty_label", null: false
    t.boolean "enabled_for_import", default: true, null: false
    t.integer "valid_from_year", null: false
    t.integer "valid_until_year"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code", "valid_from_year"], name: "index_syllabus_orgs_on_code_and_start_year", unique: true
    t.index ["enabled_for_import", "valid_from_year", "valid_until_year"], name: "index_syllabus_orgs_on_import_and_validity"
  end

  create_table "thanks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "review_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["review_id"], name: "index_thanks_on_review_id"
    t.index ["user_id", "review_id"], name: "index_thanks_on_user_id_and_review_id", unique: true
    t.index ["user_id"], name: "index_thanks_on_user_id"
  end

  create_table "timetable_entries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "lecture_id", null: false
    t.integer "year", null: false
    t.integer "term", null: false
    t.integer "day"
    t.integer "period"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "lecture_offering_id"
    t.index ["lecture_id"], name: "index_timetable_entries_on_lecture_id"
    t.index ["lecture_offering_id"], name: "index_timetable_entries_on_lecture_offering_id"
    t.index ["user_id", "year", "term", "day", "period"], name: "index_timetable_entries_on_user_and_slot", unique: true
    t.index ["user_id", "year"], name: "index_timetable_entries_on_user_id_and_year"
    t.index ["user_id"], name: "index_timetable_entries_on_user_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "provider_id", null: false
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "reviews_count", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "provider_id"], name: "index_users_on_provider_and_provider_id", unique: true
  end

  add_foreign_key "bookmarks", "lectures"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "lecture_aliases", "lectures"
  add_foreign_key "lecture_aliases", "syllabus_import_runs", column: "created_from_import_run_id"
  add_foreign_key "lecture_offering_details", "lecture_offerings"
  add_foreign_key "lecture_offerings", "lectures"
  add_foreign_key "lecture_offerings", "syllabus_import_runs", column: "first_seen_import_run_id"
  add_foreign_key "lecture_offerings", "syllabus_import_runs", column: "last_seen_import_run_id"
  add_foreign_key "lecture_offerings", "syllabus_import_runs", column: "missing_since_import_run_id"
  add_foreign_key "lecture_offerings", "syllabus_organizations"
  add_foreign_key "lectures", "lectures", column: "merged_into_lecture_id"
  add_foreign_key "offering_slots", "lecture_offerings"
  add_foreign_key "reviews", "lecture_offerings"
  add_foreign_key "reviews", "lectures", column: "lecture_id_bigint"
  add_foreign_key "reviews", "users"
  add_foreign_key "site_settings", "users", column: "last_updated_by_user_id"
  add_foreign_key "syllabus_import_rows", "lecture_offerings", column: "matched_offering_id", on_delete: :nullify
  add_foreign_key "syllabus_import_rows", "lectures", column: "matched_lecture_id"
  add_foreign_key "syllabus_import_rows", "syllabus_import_runs"
  add_foreign_key "thanks", "reviews"
  add_foreign_key "thanks", "users"
  add_foreign_key "timetable_entries", "lecture_offerings"
  add_foreign_key "timetable_entries", "lectures"
  add_foreign_key "timetable_entries", "users"
end
