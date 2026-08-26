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

ActiveRecord::Schema[8.1].define(version: 2026_08_26_071341) do
  create_table "commenters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "memory_summary"
    t.text "personality"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index [ "username" ], name: "index_commenters_on_username", unique: true
  end

  create_table "generated_comments", force: :cascade do |t|
    t.text "comments_json"
    t.string "content_hash"
    t.datetime "created_at", null: false
    t.string "file_id"
    t.datetime "updated_at", null: false
    t.integer "year"
  end

  create_table "visitor_counters", force: :cascade do |t|
    t.integer "count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
