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
    @from     = SimRoute::DEFAULT_FROM
    @to       = SimRoute::DEFAULT_TO
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
      route_form
      status_line

      LeafletMap(
        markers: my_markers,
        map_height: "58vh",
        follow: simulating?,
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

      if simulating? || routing?
        button("Stop simulation", "#b91c1c") { stop }
      else
        button("Simulate movement", "#4338ca") { start_simulation }
      end
    end
  end

  # Where "Simulate movement" drives. Locked while a drive is under way so the
  # boxes always describe the route being shown.
  #
  # A picked suggestion remembers its coordinates (@from_point / @to_point)
  # so the server need not geocode it; any later edit drops them again,
  # because the text no longer describes that place.
  def route_form
    locked = simulating? || routing?
    DIV(style: { display: "flex", gap: "0.5rem", flexWrap: "wrap", marginBottom: "0.75rem" }) do
      AddressInput(label: "Drive from", value: @from, locked: locked, near: suggestion_bias)
        .on(:text_change) { |text| mutate(@from = text, @from_point = nil) }
        .on(:pick) { |place| mutate(@from = place["label"], @from_point = [ place["lat"], place["lng"] ]) }
      AddressInput(label: "Drive to", value: @to, locked: locked, near: suggestion_bias)
        .on(:text_change) { |text| mutate(@to = text, @to_point = nil) }
        .on(:pick) { |place| mutate(@to = place["label"], @to_point = [ place["lat"], place["lng"] ]) }
    end
  end

  # Rank suggestions around where this browser is, or failing that the start
  # of the default drive.
  def suggestion_bias
    @lat.is_a?(Numeric) && @lng.is_a?(Numeric) ? [ @lat, @lng ] : SimRoute::POINTS.first[0..1]
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
      when :routing    then [ "Finding a route...", "#4338ca" ]
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
      stat("Altitude",  Geo.format_altitude(@altitude))
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

  def routing?
    @status == :routing
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
            // Altitude is null on devices without it (most desktops); JS
            // null is not Opal's nil, so convert it before it reaches Ruby.
            var altitude = position.coords.altitude;
            component.$on_fix(
              position.coords.latitude,
              position.coords.longitude,
              position.coords.accuracy,
              altitude == null ? #{nil} : altitude
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

  # Metres covered per one-second tick: about 90 km/h, so the default drive
  # takes under three minutes -- quick enough to demo.
  SIM_METRES_PER_TICK = 25

  # Drives between the two addresses so the app can be demonstrated (and
  # specced) on a desktop with no GPS, or where the location permission is
  # denied. The default pair uses the route baked into SimRoute; anything
  # else is planned by the server first.
  def start_simulation
    stop_watch
    if SimRoute.default?(@from, @to) && !@from_point && !@to_point
      drive(SimRoute::POINTS)
    else
      fetch_route
    end
  end

  def fetch_route
    mutate do
      @status = :routing
      @error  = nil
    end

    url = "/route?from=#{`encodeURIComponent(#{@from})`}&to=#{`encodeURIComponent(#{@to})`}"
    url += "&from_lat=#{@from_point[0]}&from_lng=#{@from_point[1]}" if @from_point
    url += "&to_lat=#{@to_point[0]}&to_lng=#{@to_point[1]}" if @to_point
    # Error responses carry JSON too ({ error: "..." }), so read the body
    # whatever the status and let on_route sort it out.
    %x{
      var component = #{self};
      fetch(#{url}, { headers: { Accept: 'application/json' } })
        .then(function (response) { return response.text(); })
        .then(function (text) { component.$on_route(text); })
        .catch(function () { component.$on_route_error("Couldn't reach the server -- check your connection."); });
    }
  end

  def on_route(text)
    # Stopped (or restarted) while the lookup was in flight.
    return unless routing?

    data = begin
      JSON.parse(text)
    rescue StandardError
      nil
    end
    return on_route_error("Couldn't plan that route -- try again.") unless data.is_a?(Hash)
    return on_route_error(data["error"]) if data["error"]

    drive(data["points"])
  end

  def on_route_error(message)
    return unless routing?

    on_error(message)
  end

  # Walks +points+ ([lat, lng, altitude] each), then parks at the last one.
  def drive(points)
    mutate do
      @status = :simulating
      @error  = nil
      # A new route starts a new trail rather than joining on to the old one.
      @trail  = []
    end

    @sim_points = points
    @sim_length = SimRoute.length_meters(points)
    @sim_metres = 0
    simulated_fix

    @sim_timer = every(1) do
      @sim_metres += SIM_METRES_PER_TICK
      simulated_fix
      if @sim_metres >= @sim_length
        @sim_timer.abort
        @sim_timer = nil
      end
    end
  end

  def simulated_fix
    lat, lng, altitude = SimRoute.position_at(@sim_metres, @sim_points)
    on_fix(lat, lng, 12.0, altitude)
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
  def on_fix(lat, lng, accuracy, altitude = nil)
    mutate do
      @status    = simulating? ? :simulating : :tracking
      @lat       = lat
      @lng       = lng
      @accuracy  = accuracy
      @altitude  = altitude
      @fix_at    = Time.now
      @fix_count = @fix_count.to_i + 1
      @error     = nil
      @trail     = ((@trail || []) + [ [ lat, lng ] ]).last(Location::TRAIL_LIMIT)
    end

    persist(lat, lng, accuracy, altitude)
  end

  def on_error(message)
    mutate do
      @status = :error
      @error  = message
    end
  end

  # --- writing through to the server ---------------------------------------

  def persist(lat, lng, accuracy, altitude)
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
    record.altitude    = altitude
    record.last_fix_at = now
    record.tracking    = true
    record.save

    Location.new(
      tracker: record, lat: lat, lng: lng,
      accuracy: accuracy, altitude: altitude, recorded_at: now
    ).save
  end

  def moved_enough?(lat, lng)
    return true unless @last_written

    Geo.distance_meters(@last_written[0], @last_written[1], lat, lng) >= MIN_MOVE_METRES
  end
end
