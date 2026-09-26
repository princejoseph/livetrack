require "net/http"

# Turns two street addresses into a drivable route for the simulator:
# geocode both ends (Nominatim), route between them (OSRM), then look up
# ground elevation for every point (Open-Meteo).
#
# All three are free public services with fair-use policies, which is why this
# runs server-side rather than in the browser: Nominatim requires an
# identifying User-Agent and at most one request per second, and results are
# cached so a repeated route costs nothing.
class RoutePlanner
  class Error < StandardError; end

  NOMINATIM = "https://nominatim.openstreetmap.org/search".freeze
  OSRM      = "https://router.project-osrm.org/route/v1/driving".freeze
  ELEVATION = "https://api.open-meteo.com/v1/elevation".freeze

  USER_AGENT = "livetrack (https://livetrack.fly.dev)".freeze
  TIMEOUT    = 10 # seconds, per request

  # A simulator does not need road-survey precision, and every point is
  # broadcast to other clients as the pin moves.
  MAX_POINTS = 400

  # Longer than this is not a demo drive, and would be a long elevation lookup.
  MAX_DISTANCE_M = 200_000

  NOMINATIM_LOCK = Mutex.new
  NOMINATIM_GAP  = 1.1 # seconds between requests, per their usage policy
  # Process-wide (one machine), guarded by NOMINATIM_LOCK.
  NOMINATIM_LAST = { at: 0.0 }

  # [lat, lng] if +value+ is a plausible coordinate pair, else nil. Points
  # arrive from the browser, so they are checked rather than trusted.
  def self.point(value)
    return unless value.is_a?(Array) && value.length == 2

    lat, lng = value.map { |v| Float(v, exception: false) }
    [ lat, lng ] if lat&.between?(-90, 90) && lng&.between?(-180, 180)
  end

  # +from_point+ / +to_point+ ([lat, lng]) come from a picked autocomplete
  # suggestion: that end is already located, so it is not geocoded again.
  def self.plan(from, to, from_point: nil, to_point: nil)
    key = [ "route", from.strip.downcase, from_point, to.strip.downcase, to_point ].flatten.join("|")
    Rails.cache.fetch(key, expires_in: 1.week) { new.plan(from, to, from_point:, to_point:) }
  end

  # => { points: [[lat, lng, altitude], ...], distance_m:, from_label:, to_label: }
  def plan(from, to, from_point: nil, to_point: nil)
    start  = from_point ? located(from, from_point) : geocode(from)
    finish = to_point ? located(to, to_point) : geocode(to)
    route  = route_between(start, finish)
    points = thin(route[:coordinates])

    {
      points: points.zip(elevations(points)).map { |(lat, lng), alt| [ lat, lng, alt ] },
      distance_m: route[:distance].round,
      from_label: start[:label],
      to_label: finish[:label]
    }
  end

  private

  def located(address, (lat, lng))
    { lat: lat, lng: lng, label: address }
  end

  def geocode(address)
    raise Error, "Enter both a start and an end address." if address.blank?

    results = NOMINATIM_LOCK.synchronize do
      wait = NOMINATIM_GAP - (monotonic_now - NOMINATIM_LAST[:at])
      sleep(wait) if wait.positive?
      NOMINATIM_LAST[:at] = monotonic_now
      get_json(NOMINATIM, q: address, format: "json", limit: 1)
    end

    hit = results.first
    raise Error, "Couldn't find \"#{address}\"." unless hit

    { lat: hit["lat"].to_f, lng: hit["lon"].to_f, label: hit["display_name"] }
  end

  def route_between(start, finish)
    path = "#{start[:lng]},#{start[:lat]};#{finish[:lng]},#{finish[:lat]}"
    data = get_json("#{OSRM}/#{path}", overview: "full", geometries: "geojson")
    route = data["code"] == "Ok" && data["routes"]&.first
    raise Error, "No driving route between those addresses." unless route
    raise Error, "That drive is too long for a simulation (max 200 km)." if route["distance"] > MAX_DISTANCE_M

    # OSRM speaks [lng, lat]; everything else here is [lat, lng].
    coordinates = route["geometry"]["coordinates"].map { |lng, lat| [ lat.round(5), lng.round(5) ] }
    { coordinates: coordinates.chunk_while { |a, b| a == b }.map(&:first), distance: route["distance"] }
  end

  # Keep every nth point (always including the destination) so long routes
  # stay within MAX_POINTS.
  def thin(points)
    return points if points.length <= MAX_POINTS

    step = (points.length / MAX_POINTS.to_f).ceil
    kept = points.each_slice(step).map(&:first)
    kept << points.last unless kept.last == points.last
    kept
  end

  # Open-Meteo takes up to 100 coordinates per request.
  def elevations(points)
    points.each_slice(100).flat_map do |slice|
      get_json(ELEVATION,
               latitude: slice.map(&:first).join(","),
               longitude: slice.map(&:last).join(","))
        .fetch("elevation")
    end
  rescue Error, KeyError
    # Altitude is a nice-to-have; a route without it still drives.
    Array.new(points.length)
  end

  def get_json(url, params)
    uri = URI(url)
    uri.query = URI.encode_www_form(params)
    request = Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT, "Accept" => "application/json")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(request)
    end
    raise Error, "The map service is busy -- try again in a moment." unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, JSON::ParserError
    raise Error, "The map service is unavailable -- try again in a moment."
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
