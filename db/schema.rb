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

ActiveRecord::Schema[8.0].define(version: 2026_09_26_101659) do
  create_table "hyperstack_connections", force: :cascade do |t|
    t.string "channel"
    t.string "session"
    t.datetime "created_at"
    t.datetime "expires_at"
    t.datetime "refresh_at"
  end

  create_table "hyperstack_queued_messages", force: :cascade do |t|
    t.text "data"
    t.integer "connection_id"
  end

  create_table "locations", force: :cascade do |t|
    t.integer "tracker_id", null: false
    t.float "lat", null: false
    t.float "lng", null: false
    t.float "accuracy"
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "altitude"
    t.index ["tracker_id", "recorded_at"], name: "index_locations_on_tracker_id_and_recorded_at"
    t.index ["tracker_id"], name: "index_locations_on_tracker_id"
  end

  create_table "trackers", force: :cascade do |t|
    t.string "name", null: false
    t.string "color", null: false
    t.boolean "tracking", default: false, null: false
    t.float "lat"
    t.float "lng"
    t.float "accuracy"
    t.datetime "last_fix_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "altitude"
    t.index ["tracking"], name: "index_trackers_on_tracking"
  end

  add_foreign_key "locations", "trackers"
end
