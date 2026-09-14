require "rails_helper"

RSpec.describe Tracker do
  def tracker(attrs = {})
    Tracker.create!({ name: "Test Heron", color: "#2563eb" }.merge(attrs))
  end

  describe "the live scope" do
    it "includes a tracker that is tracking and has a position" do
      subject = tracker(tracking: true, lat: 12.97, lng: 77.59, last_fix_at: Time.current)
      expect(Tracker.live).to include(subject)
    end

    it "excludes a tracker that has stopped" do
      subject = tracker(tracking: false, lat: 12.97, lng: 77.59, last_fix_at: Time.current)
      expect(Tracker.live).not_to include(subject)
    end

    it "excludes a tracker that has never reported a position" do
      subject = tracker(tracking: true)
      expect(Tracker.live).not_to include(subject)
    end
  end

  describe "staleness" do
    it "is not stale just after a fix" do
      expect(tracker(last_fix_at: Time.current)).not_to be_stale
    end

    it "is stale once the last fix is older than the window" do
      old = tracker(last_fix_at: (Tracker::STALE_AFTER + 30).seconds.ago)
      expect(old).to be_stale
    end

    it "is stale when it has never reported" do
      expect(tracker).to be_stale
    end
  end

  it "generates a name and a colour from the configured lists" do
    identity = Tracker.generate_identity
    adjective, animal = identity[:name].split(" ")
    expect(Tracker::ADJECTIVES).to include(adjective)
    expect(Tracker::ANIMALS).to include(animal)
    expect(Tracker::COLORS).to include(identity[:color])
  end
end
