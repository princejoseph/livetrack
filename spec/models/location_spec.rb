require "rails_helper"

RSpec.describe Location do
  let(:subject_tracker) { Tracker.create!(name: "Test Otter", color: "#059669") }

  def record_fix(index)
    Location.create!(
      tracker: subject_tracker, lat: 12.97 + (index * 0.0001), lng: 77.59,
      accuracy: 10, recorded_at: index.seconds.from_now
    )
  end

  it "keeps the trail bounded to TRAIL_LIMIT points per tracker" do
    (Location::TRAIL_LIMIT + 15).times { |i| record_fix(i) }
    expect(subject_tracker.locations.count).to eq(Location::TRAIL_LIMIT)
  end

  it "prunes the oldest points, keeping the newest" do
    (Location::TRAIL_LIMIT + 5).times { |i| record_fix(i) }
    kept = subject_tracker.locations.newest_first.first
    expect(kept.recorded_at).to be > Time.current
    expect(subject_tracker.locations.minimum(:recorded_at)).to be > 4.seconds.from_now
  end

  it "does not prune another tracker's trail" do
    other = Tracker.create!(name: "Test Lynx", color: "#d97706")
    Location.create!(tracker: other, lat: 1.0, lng: 1.0, recorded_at: Time.current)
    (Location::TRAIL_LIMIT + 5).times { |i| record_fix(i) }
    expect(other.locations.count).to eq(1)
  end

  it "rejects impossible coordinates" do
    record = Location.new(tracker: subject_tracker, lat: 120, lng: 0, recorded_at: Time.current)
    expect(record).not_to be_valid
  end
end
