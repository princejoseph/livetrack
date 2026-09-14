class CreateTrackersAndLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :trackers do |t|
      # Anonymous identity. There is deliberately no secret column here: the
      # session->tracker mapping lives in Rails' encrypted session cookie
      # (session[:tracker_id]), so every column below is safe to broadcast to
      # every connected client, which is exactly what the "everyone" map needs.
      t.string  :name,  null: false
      t.string  :color, null: false

      # True while a browser is actively reporting fixes. A boolean flipped by
      # a real DB write broadcasts reliably, unlike a "seen in the last N
      # minutes" window, which would have to change without any write.
      t.boolean :tracking, null: false, default: false

      # Latest fix, denormalised onto the tracker so the "everyone" map only
      # has to watch one row per person to move a marker.
      t.float    :lat
      t.float    :lng
      t.float    :accuracy
      t.datetime :last_fix_at

      t.timestamps
    end
    add_index :trackers, :tracking

    # One row per fix, used to draw the trail behind a marker. Pruned to the
    # most recent Location::TRAIL_LIMIT points per tracker on create.
    create_table :locations do |t|
      t.references :tracker, null: false, foreign_key: true
      t.float      :lat,      null: false
      t.float      :lng,      null: false
      t.float      :accuracy
      t.datetime   :recorded_at, null: false

      t.timestamps
    end
    add_index :locations, [ :tracker_id, :recorded_at ]
  end
end
