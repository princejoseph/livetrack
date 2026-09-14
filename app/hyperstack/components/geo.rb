# Geodesic helpers shared by the tracking page and the map.
# Plain module methods so they work identically on server and client.
module Geo
  EARTH_RADIUS_M = 6_371_000

  # Great-circle distance in metres. Used to decide whether a new GPS fix has
  # moved far enough to be worth a server write.
  def self.distance_meters(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180
    d_lat = (lat2 - lat1) * rad
    d_lng = (lng2 - lng1) * rad
    a = (Math.sin(d_lat / 2)**2) +
        (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(d_lng / 2)**2))
    EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  # Numeric check rather than truthiness: an unloaded HyperModel attribute is
  # a truthy DummyValue that format() cannot render.
  def self.format_coord(value)
    return "--" unless value.is_a?(Numeric)

    format("%.5f", value)
  end
end
