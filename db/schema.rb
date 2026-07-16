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

ActiveRecord::Schema[7.0].define(version: 2026_07_13_000003) do
  create_table "bookmarks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "lecture_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lecture_id"], name: "index_bookmarks_on_lecture_id"
    t.index ["user_id", "lecture_id"], name: "index_bookmarks_on_user_id_and_lecture_id", unique: true
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "lectures", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "title"
    t.string "lecturer"
    t.string "faculty"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lecturer"], name: "index_lectures_on_lecturer"
    t.index ["title", "lecturer", "faculty"], name: "index_lectures_on_title_lecturer_faculty", unique: true
    t.index ["title", "lecturer"], name: "index_lectures_on_title_and_lecturer"
    t.index ["title"], name: "index_lectures_on_title"
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
    t.index ["lecture_id"], name: "index_lecture_offerings_on_lecture_id"
    t.index ["year", "registration_code"], name: "index_lecture_offerings_on_year_and_registration_code", unique: true
    t.index ["year", "term_code"], name: "index_lecture_offerings_on_year_and_term_code"
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
    t.index ["lecture_id", "content_difficulty"], name: "index_reviews_on_lecture_id_and_content_difficulty"
    t.index ["lecture_id", "content_quality"], name: "index_reviews_on_lecture_id_and_content_quality"
    t.index ["lecture_id", "period_year"], name: "index_reviews_on_lecture_id_and_period_year"
    t.index ["lecture_id"], name: "index_reviews_on_lecture_id"
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

  create_table "timetable_entries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "lecture_id", null: false
    t.integer "year", null: false
    t.integer "term", null: false
    t.integer "day"
    t.integer "period"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lecture_id"], name: "index_timetable_entries_on_lecture_id"
    t.index ["user_id", "year", "term", "day", "period"], name: "index_timetable_entries_on_user_and_slot", unique: true
    t.index ["user_id", "year"], name: "index_timetable_entries_on_user_id_and_year"
    t.index ["user_id"], name: "index_timetable_entries_on_user_id"
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
  add_foreign_key "lecture_offerings", "lectures"
  add_foreign_key "offering_slots", "lecture_offerings"
  add_foreign_key "reviews", "users"
  add_foreign_key "site_settings", "users", column: "last_updated_by_user_id"
  add_foreign_key "timetable_entries", "lectures"
  add_foreign_key "timetable_entries", "users"
  add_foreign_key "thanks", "reviews"
  add_foreign_key "thanks", "users"
end
