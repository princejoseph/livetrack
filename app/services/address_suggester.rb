require "net/http"

# Search-as-you-type suggestions for the simulator's address boxes, from
# Photon (photon.komoot.io, OpenStreetMap data). Nominatim -- which
# RoutePlanner uses to geocode typed addresses -- forbids autocomplete use in
# its usage policy; Photon is built for it.
#
# Photon is a free shared service that throttles bursts, and it lacks the US
# census address data Nominatim has, so it suggests streets and places well
# but often not house numbers. Suggestions are therefore best-effort: any
# failure is an empty list, never an error the user sees.
class AddressSuggester
  PHOTON     = "https://photon.komoot.io/api/".freeze
  USER_AGENT = RoutePlanner::USER_AGENT
  TIMEOUT    = 4 # seconds -- a late suggestion is a useless one
  LIMIT      = 5
  MIN_LENGTH = 3

  # => [{ label:, lat:, lng: }, ...]
  #
  # +near+ ([lat, lng]) ranks nearby matches first. It is rounded for the
  # cache key so that nearby users share cached results.
  def self.suggest(query, near: nil)
    query = query.to_s.strip.gsub(/\s+/, " ")
    return [] if query.length < MIN_LENGTH

    bias = near&.map { |value| value.round(1) }
    key  = [ "suggest", query.downcase, bias ].flatten.join("|")
    # A failed lookup is nil and skip_nil keeps it out of the cache -- a
    # throttled burst must not read back as "no matches" for a day.
    Rails.cache.fetch(key, expires_in: 1.day, skip_nil: true) { new.suggest(query, bias) } || []
  end

  # Suggestions, or nil if Photon could not be asked.
  def suggest(query, bias)
    params = { q: query, limit: LIMIT, lang: "en" }
    params.merge!(lat: bias[0], lon: bias[1]) if bias

    features = fetch(params)&.fetch("features", nil)
    return unless features.is_a?(Array)

    features.filter_map { |feature| suggestion(feature) }.uniq { |s| s[:label] }
  end

  private

  def suggestion(feature)
    return unless feature.is_a?(Hash)

    lng, lat = feature.dig("geometry", "coordinates")
    return unless lat.is_a?(Numeric) && lng.is_a?(Numeric)

    { label: label_for(feature["properties"] || {}), lat: lat, lng: lng }
  end

  # "Oceanside Pier, Oceanside, California" /
  # "260 3rd Avenue, Chula Vista, California" -- the country only when it is
  # not the US, where every result would otherwise end in "United States".
  def label_for(props)
    street = [ props["housenumber"], props["street"] ].compact.join(" ").presence
    parts = [ props["name"], street, props["city"] || props["county"], props["state"] ]
    parts << props["country"] unless props["countrycode"] == "US"
    parts.compact.map(&:to_s).reject(&:empty?).uniq.join(", ")
  end

  def fetch(params)
    uri = URI(PHOTON)
    uri.query = URI.encode_www_form(params)
    request = Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT, "Accept" => "application/json")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(request)
    end
    # Photon answers a throttled burst with an empty body.
    return unless response.is_a?(Net::HTTPSuccess) && response.body.present?

    data = JSON.parse(response.body)
    data if data.is_a?(Hash)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError
    nil
  end
end
