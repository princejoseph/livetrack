class AddAltitudeToTrackersAndLocations < ActiveRecord::Migration[8.0]
  # Metres above sea level. Nullable: many devices (most desktops) report no
  # altitude at all.
  def change
    add_column :trackers, :altitude, :float
    add_column :locations, :altitude, :float
  end
end
