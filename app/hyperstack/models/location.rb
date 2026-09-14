# Lives in app/hyperstack/models so it is available on both server and client.
class Location < ApplicationRecord
  belongs_to :tracker

  # How many points of trail to keep per tracker. Bounded on purpose: every
  # Location row is broadcast to every connected client, so this is what keeps
  # the "everyone" map's payload from growing without limit.
  TRAIL_LIMIT = 50

  scope :newest_first, -> { order(recorded_at: :desc) }

  unless RUBY_ENGINE == "opal"
    validates :lat, presence: true,
                    numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
    validates :lng, presence: true,
                    numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

    after_create :prune_trail

    # Destroying the surplus rows (rather than leaving them) also broadcasts
    # the removal, so long-running clients drop old trail points too.
    def prune_trail
      surplus = Location.where(tracker_id: tracker_id)
                        .newest_first
                        .offset(TRAIL_LIMIT)
      surplus.each(&:destroy)
    end
  end
end
