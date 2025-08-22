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

ActiveRecord::Schema[7.0].define(version: 2025_08_21_074843) do
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

  create_table "review_periods", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "period_name", null: false, comment: "期間名 (例: 2025-spring)"
    t.datetime "start_date", null: false, comment: "期間開始日"
    t.datetime "end_date", null: false, comment: "期間終了日"
    t.boolean "is_active", default: false, null: false, comment: "現在有効な期間かを示すフラグ"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_review_periods_on_is_active"
    t.index ["period_name"], name: "index_review_periods_on_period_name", unique: true
    t.index ["start_date", "end_date"], name: "index_review_periods_on_start_date_and_end_date"
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

  create_table "thanks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "review_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["review_id"], name: "index_thanks_on_review_id"
    t.index ["user_id", "review_id"], name: "index_thanks_on_user_id_and_review_id", unique: true
    t.index ["user_id"], name: "index_thanks_on_user_id"
  end

  create_table "user_review_period_counts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false, comment: "ユーザーID"
    t.bigint "review_period_id", null: false, comment: "レビュー期間ID"
    t.integer "reviews_count", default: 0, null: false, comment: "期間内のレビュー投稿数"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["review_period_id"], name: "index_user_review_period_counts_on_review_period_id"
    t.index ["user_id", "review_period_id"], name: "index_user_period_counts_unique", unique: true
    t.index ["user_id"], name: "index_user_review_period_counts_on_user_id"
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
  add_foreign_key "reviews", "users"
  add_foreign_key "thanks", "reviews"
  add_foreign_key "thanks", "users"
  add_foreign_key "user_review_period_counts", "review_periods"
  add_foreign_key "user_review_period_counts", "users"
end
