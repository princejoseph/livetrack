# Page 2: every browser currently reporting, with markers that move as their
# fixes arrive over ActionCable. Nothing here polls -- the render re-runs
# because HyperModel broadcasts each Tracker/Location change.
class EveryoneMap < HyperComponent
  param :tracker_id

  # A tracker that stopped reporting without a clean "Stop" (tab closed, phone
  # asleep) is faded after FADE_AFTER and dropped after DROP_AFTER. This is
  # evaluated on every tick, so it needs no server-side sweeper.
  FADE_AFTER = 60
  DROP_AFTER = 180

  after_mount do
    # Re-render once a second so the "seconds ago" text and the fade/drop
    # thresholds advance even when no new fix arrives.
    every(1) { mutate @tick = Time.now }
  end

  render do
    DIV(style: { fontFamily: "system-ui, -apple-system, sans-serif", padding: "1rem", maxWidth: "960px", margin: "0 auto" }) do
      PageNav(active: :everyone, tracker_name: me.name, tracker_color: me.color)

      H1(style: { fontSize: "1.5rem", margin: "0 0 0.25rem" }) { "Everyone" }
      P(style: { color: "#6b7280", fontSize: "1rem", margin: "0 0 1rem" }) do
        "Live positions of every browser currently tracking. Updates arrive over ActionCable -- this page never reloads."
      end

      LeafletMap(
        markers: everyone_markers,
        map_height: "58vh",
        empty_message: "Nobody is tracking yet. Open the Track me page to appear here."
      )

      roster
    end
  end

  def me
    Tracker.find(tracker_id)
  end

  # Only trackers whose coordinates have actually arrived. A record that is
  # still loading exposes DummyValue attributes -- truthy, but not numbers --
  # so this filters on type rather than truthiness.
  def visible_trackers
    Tracker.live.select do |tracker|
      tracker.lat.is_a?(Numeric) && tracker.lng.is_a?(Numeric) &&
        age_of(tracker) < DROP_AFTER
    end
  end

  def everyone_markers
    visible_trackers.map do |tracker|
      {
        id:       tracker.id,
        lat:      tracker.lat,
        lng:      tracker.lng,
        color:    tracker.color,
        label:    tracker.id == me.id ? "#{tracker.name} (you)" : tracker.name,
        accuracy: tracker.accuracy,
        stale:    age_of(tracker) > FADE_AFTER,
        me:       tracker.id == me.id,
        trail:    trail_for(tracker)
      }
    end
  end

  # `order`/`limit` are server-only in HyperModel, so the association is sorted
  # client-side. Sorting by id rather than recorded_at keeps it to integer
  # comparison, which is safer under Opal than Time comparison.
  def trail_for(tracker)
    tracker.locations
           .sort_by(&:id)
           .last(Location::TRAIL_LIMIT)
           .map { |location| [location.lat, location.lng] }
           .select { |point| point[0].is_a?(Numeric) && point[1].is_a?(Numeric) }
  end

  def age_of(tracker)
    tracker.seconds_since_fix || DROP_AFTER + 1
  end

  def roster
    DIV(style: { marginTop: "1rem" }) do
      H2(style: { fontSize: "1.1rem", margin: "0 0 0.5rem", color: "#374151" }) do
        "#{visible_trackers.length} tracking now"
      end

      visible_trackers.sort_by(&:name).each do |tracker|
        DIV(
          key: tracker.id,
          style: {
            display: "flex", alignItems: "center", gap: "0.65rem",
            padding: "0.6rem 0.75rem", marginBottom: "0.4rem",
            background: "#f3f4f6", borderRadius: "10px",
            opacity: age_of(tracker) > FADE_AFTER ? "0.55" : "1"
          }
        ) do
          SPAN(style: {
                 width: "14px", height: "14px", borderRadius: "50%",
                 background: tracker.color, flex: "0 0 auto",
                 border: "2px solid #fff", boxShadow: "0 1px 4px rgba(0,0,0,.35)"
               })
          SPAN(style: { fontSize: "1rem", fontWeight: "600", color: "#111827" }) do
            tracker.id == me.id ? "#{tracker.name} (you)" : tracker.name
          end
          SPAN(style: { fontSize: "0.9rem", color: "#6b7280" }) do
            "#{Geo.format_coord(tracker.lat)}, #{Geo.format_coord(tracker.lng)}"
          end
          SPAN(style: { marginLeft: "auto", fontSize: "0.9rem", color: "#6b7280" }) do
            "#{age_of(tracker)}s ago"
          end
        end
      end
    end
  end
end
