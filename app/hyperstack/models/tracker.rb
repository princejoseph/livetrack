# Lives in app/hyperstack/models (not app/models) so Zeitwerk loads it on the
# server AND Opal compiles it for the client.
class Tracker < ApplicationRecord
  has_many :locations, dependent: :destroy

  # Markers older than this are drawn faded rather than hidden, so a browser
  # that vanished without a clean stop decays instead of disappearing.
  STALE_AFTER = 60 # seconds

  ADJECTIVES = %w[Swift Quiet Amber Clever Roaming Bright Nimble Wander
                  Copper Lucky Silent Brave].freeze
  ANIMALS    = %w[Heron Otter Falcon Marten Ibex Tapir Lynx Gecko
                  Puffin Kite Shrew Civet].freeze
  # Picked to stay distinguishable against OpenStreetMap's muted tiles.
  COLORS     = %w[#e11d48 #2563eb #059669 #d97706 #7c3aed #db2777
                  #0891b2 #65a30d].freeze

  # `tracking` is a column, so the scope needs a different name.
  # The client: filter lets HyperModel decide locally whether a freshly
  # broadcast row belongs in this scope, instead of refetching from the server
  # on every position change.
  scope :live,
        -> { where(tracking: true).where.not(lat: nil) },
        client: -> { tracking && lat }

  def coordinates?
    lat && lng
  end

  # Seconds since the last fix. Rendered as "live" vs "stale" on the map.
  # Written to be Opal-safe: Time subtraction only, no ActiveSupport helpers.
  def seconds_since_fix
    stamp = last_fix_at
    # While HyperModel is still fetching, an attribute reads back as a
    # DummyValue. It is *truthy*, so `unless stamp` would not catch it, but it
    # reports nil? == true -- and Time arithmetic on it raises
    # "no implicit conversion of DummyValue into Integer".
    return nil if stamp.nil?

    (Time.now - stamp).to_i
  end

  def stale?
    age = seconds_since_fix
    age.nil? || age > STALE_AFTER
  end

  unless RUBY_ENGINE == 'opal'
    def self.generate_identity
      {
        name: "#{ADJECTIVES.sample} #{ANIMALS.sample}",
        color: COLORS.sample
      }
    end
  end
end
