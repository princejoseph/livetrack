# backtick_javascript: true
# Page 1: watch this browser's GPS and draw it on a live map, writing each
# accepted fix through HyperModel so the "everyone" page sees it move.
class TrackMe < HyperComponent
  param :tracker_id

  # Never write to the server more often than this, however chatty the GPS is.
  HARD_MIN_INTERVAL = 1.0
  # Beyond the hard floor, only write on a real interval or a real move --
  # a stationary phone still emits fixes constantly.
  MIN_INTERVAL   = 3.0
  MIN_MOVE_METRES = 5.0

  before_mount do
    @status   = :idle
    @fix_count = 0
    @error    = nil
  end

  after_mount do
    # Drives the "N seconds ago" readout and the staleness fade.
    every(1) { mutate @tick = Time.now }
  end

  before_unmount { stop_watch }

  def me
    Tracker.find(tracker_id)
  end

  render do
    DIV(style: { fontFamily: "system-ui, -apple-system, sans-serif", padding: "1rem", maxWidth: "960px", margin: "0 auto" }) do
      PageNav(active: :me, tracker_name: me.name, tracker_color: me.color)

      H1(style: { fontSize: "1.5rem", margin: "0 0 0.25rem" }) { "Track me" }
      P(style: { color: "#6b7280", fontSize: "1rem", margin: "0 0 1rem" }) do
        "Your position is written to the server as you move. Open the Everyone page on another device to watch it."
      end

      controls
      status_line

      LeafletMap(
        markers: my_markers,
        map_height: "58vh",
        empty_message: @status == :idle ? "Press Start tracking to begin." : "Waiting for a position fix..."
      )

      readout
    end
  end

  # --- UI pieces ------------------------------------------------------------

  def controls
    DIV(style: { display: "flex", gap: "0.5rem", flexWrap: "wrap", marginBottom: "0.75rem" }) do
      if tracking?
        button("Stop tracking", "#b91c1c") { stop }
      elsif simulating?
        # Labelled as a switch rather than a second "Start", so it is obvious
        # this replaces the simulation with the device's real GPS.
        button("Use real GPS", "#047857") { start }
      else
        button("Start tracking", "#047857") { start }
      end

      if simulating?
        button("Stop simulation", "#b91c1c") { stop }
      else
        button("Simulate movement", "#4338ca") { start_simulation }
      end
    end
  end

  def button(label, color, &handler)
    BUTTON(
      style: {
        padding: "0.65rem 1rem", fontSize: "1rem", border: "none",
        borderRadius: "10px", background: color, color: "#fff", cursor: "pointer"
      }
    ) { label }.on(:click, &handler)
  end

  def status_line
    text, color =
      case @status
      when :idle       then [ "Not tracking", "#6b7280" ]
      when :locating   then [ "Waiting for GPS...", "#b45309" ]
      when :tracking   then [ "Live - #{@fix_count} fixes received", "#047857" ]
      when :simulating then [ "Simulated movement - #{@fix_count} fixes", "#4338ca" ]
      when :error      then [ @error.to_s, "#b91c1c" ]
      else [ "", "#6b7280" ]
      end

    DIV(style: { fontSize: "1rem", color: color, marginBottom: "0.75rem", minHeight: "1.4rem" }) { text }
  end

  def readout
    DIV(style: {
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))",
          gap: "0.75rem", marginTop: "1rem"
        }) do
      stat("Latitude",  Geo.format_coord(@lat))
      stat("Longitude", Geo.format_coord(@lng))
      stat("Accuracy",  @accuracy ? "#{@accuracy.round} m" : "--")
      stat("Last fix",  @fix_at ? "#{(Time.now - @fix_at).to_i}s ago" : "--")
    end
  end

  def stat(label, value)
    DIV(style: { padding: "0.75rem", background: "#f3f4f6", borderRadius: "10px" }) do
      DIV(style: { fontSize: "0.85rem", color: "#6b7280" }) { label }
      DIV(style: { fontSize: "1.1rem", fontWeight: "600", color: "#111827" }) { value }
    end
  end

  # --- state ----------------------------------------------------------------

  def tracking?
    @status == :tracking || @status == :locating
  end

  def simulating?
    @status == :simulating
  end

  def my_markers
    return [] unless @lat && @lng

    [ {
      id: "me",
      lat: @lat,
      lng: @lng,
      color: me.color,
      label: me.name,
      accuracy: @accuracy,
      stale: false,
      me: true,
      trail: @trail || []
    } ]
  end

  # --- geolocation ----------------------------------------------------------

  def start
    return if @watch_id

    # Switching from the simulator to real GPS: drop the simulated fixes first.
    stop_watch if simulating?

    unless geolocation_available?
      mutate do
        @status = :error
        @error  = "This browser does not expose the Geolocation API."
      end
      return
    end

    mutate do
      @status = :locating
      @error  = nil
    end

    # The IIFE returns watchPosition's id so Ruby can hold it for clearWatch.
    @watch_id = %x{
      (function () {
        var component = #{self};
        return navigator.geolocation.watchPosition(
          function (position) {
            component.$on_fix(
              position.coords.latitude,
              position.coords.longitude,
              position.coords.accuracy
            );
          },
          function (failure) {
            component.$on_error(failure.message || "Location unavailable");
          },
          { enableHighAccuracy: true, maximumAge: 2000, timeout: 20000 }
        );
      })()
    }
  end

  def geolocation_available?
    `!!(navigator.geolocation && navigator.geolocation.watchPosition)`
  end

  # Walks a small circle so the app can be demonstrated (and specced) on a
  # desktop with no GPS, or where the location permission is denied.
  def start_simulation
    stop_watch
    mutate do
      @status = :simulating
      @error  = nil
    end

    @sim_step = 0
    base_lat  = @lat || 12.9716   # Bengaluru
    base_lng  = @lng || 77.5946

    @sim_timer = every(2) do
      @sim_step += 1
      radius = 0.0012
      on_fix(
        base_lat + (radius * Math.sin(@sim_step / 6.0)),
        base_lng + (radius * Math.cos(@sim_step / 6.0)),
        12.0
      )
    end
  end

  def stop
    stop_watch
    mutate @status = :idle
    record = me
    record.tracking = false
    record.save
  end

  def stop_watch
    `navigator.geolocation.clearWatch(#{@watch_id})` if @watch_id
    @watch_id = nil
    @sim_timer.abort if @sim_timer
    @sim_timer = nil
  end

  # Called from the geolocation callback (and the simulator).
  def on_fix(lat, lng, accuracy)
    mutate do
      @status    = simulating? ? :simulating : :tracking
      @lat       = lat
      @lng       = lng
      @accuracy  = accuracy
      @fix_at    = Time.now
      @fix_count = @fix_count.to_i + 1
      @error     = nil
      @trail     = ((@trail || []) + [ [ lat, lng ] ]).last(Location::TRAIL_LIMIT)
    end

    persist(lat, lng, accuracy)
  end

  def on_error(message)
    mutate do
      @status = :error
      @error  = message
    end
  end

  # --- writing through to the server ---------------------------------------

  def persist(lat, lng, accuracy)
    now = Time.now
    if @last_write_at
      elapsed = now - @last_write_at
      return if elapsed < HARD_MIN_INTERVAL
      return if elapsed < MIN_INTERVAL && !moved_enough?(lat, lng)
    end

    @last_write_at = now
    @last_written  = [ lat, lng ]

    record = me
    record.lat         = lat
    record.lng         = lng
    record.accuracy    = accuracy
    record.last_fix_at = now
    record.tracking    = true
    record.save

    Location.new(
      tracker: record, lat: lat, lng: lng,
      accuracy: accuracy, recorded_at: now
    ).save
  end

  def moved_enough?(lat, lng)
    return true unless @last_written

    Geo.distance_meters(@last_written[0], @last_written[1], lat, lng) >= MIN_MOVE_METRES
  end
end
