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

ActiveRecord::Schema[7.0].define(version: 2025_04_27_071449) do
  create_table "lectures", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "title"
    t.string "lecturer"
    t.string "faculty"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["title", "lecturer", "faculty"], name: "index_lectures_on_title_lecturer_faculty", unique: true
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
  end

end
