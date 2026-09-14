# backtick_javascript: true
# Wraps a Leaflet map. Leaflet is imperative and React is declarative, so this
# component owns the map instance and reconciles it by hand: `markers` comes in
# as plain Ruby hashes, and after every render the layers are updated to match.
#
# Marker hash shape:
#   { id:, lat:, lng:, color:, label:, accuracy:, stale:, me:, trail: [[lat,lng], ...] }
class LeafletMap < HyperComponent
  param :markers, default: []
  param :map_height, default: "60vh"
  param :empty_message, default: "Waiting for a position fix..."

  # Zoom used when focusing on a single marker; a whole-group fit picks its own.
  SOLO_ZOOM = 16

  after_mount :build_map
  after_update :sync_layers

  before_unmount do
    # Leaflet keeps listeners on window/document, so drop the map explicitly
    # rather than relying on the node disappearing.
    `#{@map}.remove()` if @map
    @map = nil
  end

  render do
    DIV(style: { position: "relative" }) do
      DIV(
        # `ref:` is one of the few non-event hash params Hyperstack forwards --
        # it hands back the raw DOM node, which is what Leaflet needs.
        ref: ->(node) { @node = node },
        style: {
          height: map_height,
          width: "100%",
          borderRadius: "14px",
          overflow: "hidden",
          background: "#e5e7eb"
        }
      )

      BUTTON(
        style: {
          position: "absolute",
          top: "12px",
          right: "12px",
          # Leaflet's own controls sit at z-index 1000, so clear them.
          zIndex: 1200,
          padding: "0.5rem 0.75rem",
          fontSize: "1rem",
          border: "none",
          borderRadius: "10px",
          background: "rgba(17,24,39,0.85)",
          color: "#fff",
          cursor: "pointer"
        }
      ) { "Recenter" }.on(:click) { recenter }

      if markers.empty?
        DIV(
          style: {
            position: "absolute", top: "50%", left: "50%",
            transform: "translate(-50%,-50%)", zIndex: 1200,
            padding: "0.6rem 1rem", borderRadius: "10px",
            background: "rgba(255,255,255,0.92)", color: "#374151",
            fontSize: "1rem", textAlign: "center", maxWidth: "80%"
          }
        ) { empty_message }
      end
    end
  end

  # --- Leaflet plumbing -----------------------------------------------------
  # Every Ruby value referenced inside %x{}/backticks is passed with an
  # explicit #{...} interpolation; bare locals are not reliably substituted.

  def build_map
    # Deliberately not `!@node`: Opal compiles unary ! to Opal.not(x), which
    # reads x['$!'], and @node is a raw DOM element from `ref:` with no Ruby
    # methods on it. `if`/`unless` use $truthy, which handles natives.
    return if @map
    return unless @node

    @layers = {}
    @fitted = false

    @map = `L.map(#{@node}, { zoomControl: true, attributionControl: true })`
    # A world view until the first fix arrives, so the tiles are never blank.
    `#{@map}.setView([20.0, 10.0], 2)`

    tiles = `L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; OpenStreetMap contributors' })`
    `#{tiles}.addTo(#{@map})`

    # The container is sized by CSS that may not have settled when the map is
    # constructed; without this Leaflet caches a wrong size and tiles tile
    # into the corner only.
    %x{
      var the_map = #{@map};
      setTimeout(function () {
        // The component can unmount (and map.remove()) before this fires, which
        // leaves the panes gone and invalidateSize() throwing on _leaflet_pos.
        if (the_map && the_map._container && the_map._loaded) {
          the_map.invalidateSize();
        }
      }, 120);
    }

    sync_layers
  end

  # A coordinate is usable only if it is really a number. Truthiness is not
  # enough: an unloaded HyperModel attribute arrives as a DummyValue, which is
  # truthy but is_a?(Numeric) == false, and feeding one to Leaflet breaks the
  # whole map.
  def placed?(marker)
    marker[:lat].is_a?(Numeric) && marker[:lng].is_a?(Numeric)
  end

  # Coerce to a JS primitive before handing a value to Leaflet.
  #
  # HyperModel attribute values arrive on the client as *boxed* JS objects
  # (typeof 'object'), not primitives -- they behave correctly in Ruby, but
  # Leaflet's toLatLng() checks `typeof a[0] !== 'object'` and silently
  # returns null for a boxed pair, so L.marker(...)._latlng ends up nil and
  # addTo() then throws "Cannot read properties of null (reading 'lat')".
  # Values that come straight from a browser API (the Geolocation callback on
  # the tracking page) are already primitive, which is why this only bites on
  # data that came back through HyperModel.
  def num(value)
    `Number(#{value})`
  end

  def str(value)
    `String(#{value})`
  end

  def latlng(marker)
    `L.latLng(#{num(marker[:lat])}, #{num(marker[:lng])})`
  end

  def sync_layers
    return unless @map

    present = []
    markers.each do |marker|
      next unless placed?(marker)

      present << marker[:id]
      layer = (@layers[marker[:id]] ||= create_layer(marker))
      update_layer(layer, marker)
    end

    (@layers.keys - present).each { |id| destroy_layer(@layers.delete(id)) }

    fit_once
  end

  def create_layer(marker)
    position = latlng(marker)
    color    = str(marker[:color])

    handle = `L.marker(#{position}, { icon: #{build_icon(marker)} })`
    `#{handle}.addTo(#{@map})`
    `#{handle}.bindTooltip(#{str(marker[:label])}, { permanent: true, direction: 'top', offset: [0, -12], className: 'lt-label' })`

    trail = `L.polyline([], { color: #{color}, weight: 3, opacity: 0.6 })`
    `#{trail}.addTo(#{@map})`

    # Accuracy halo -- honest about how precise the fix actually is.
    halo = `L.circle(#{position}, { radius: 0, color: #{color}, weight: 1, opacity: 0.3, fillOpacity: 0.08 })`
    `#{halo}.addTo(#{@map})`

    # Remember what the layer was last drawn with, so update_layer can tell
    # when the appearance actually needs rebuilding.
    {
      handle: handle, trail: trail, halo: halo,
      stale: marker[:stale], color: marker[:color], label: marker[:label]
    }
  end

  def update_layer(layer, marker)
    position = latlng(marker)
    handle   = layer[:handle]
    `#{handle}.setLatLng(#{position})`

    # Rebuild the icon when anything it is drawn from changes. This is not
    # only a repaint optimisation: a record can reach the map before HyperModel
    # has loaded its columns, in which case name and colour arrive as
    # DummyValues that render as empty strings. Reconciling them here is what
    # fills in the colour and the label once the real values turn up.
    if layer[:stale] != marker[:stale] || layer[:color] != marker[:color]
      layer[:stale] = marker[:stale]
      layer[:color] = marker[:color]
      `#{handle}.setIcon(#{build_icon(marker)})`
      `#{layer[:trail]}.setStyle({ color: #{str(marker[:color])} })`
      `#{layer[:halo]}.setStyle({ color: #{str(marker[:color])} })`
    end

    if layer[:label] != marker[:label]
      layer[:label] = marker[:label]
      `#{handle}.setTooltipContent(#{str(marker[:label])})`
    end

    points = (marker[:trail] || [])
             .select { |point| point[0].is_a?(Numeric) && point[1].is_a?(Numeric) }
             .map { |point| `L.latLng(#{num(point[0])}, #{num(point[1])})` }
    `#{layer[:trail]}.setLatLngs(#{points})`

    halo = layer[:halo]
    `#{halo}.setLatLng(#{position})`
    `#{halo}.setRadius(#{num(marker[:accuracy] || 0)})`
  end

  def destroy_layer(layer)
    return unless layer

    `#{@map}.removeLayer(#{layer[:handle]})`
    `#{@map}.removeLayer(#{layer[:trail]})`
    `#{@map}.removeLayer(#{layer[:halo]})`
  end

  # A CSS-only divIcon: Leaflet's default marker needs image files, which is an
  # extra failure mode, and a coloured dot per person is what this map wants.
  def build_icon(marker)
    ring    = marker[:me] ? "3px solid #111827" : "2px solid #ffffff"
    opacity = marker[:stale] ? "0.4" : "1"
    html =
      "<span style=\"display:block;width:18px;height:18px;border-radius:50%;" \
      "background:#{marker[:color]};border:#{ring};" \
      "box-shadow:0 1px 5px rgba(0,0,0,0.45);opacity:#{opacity}\"></span>"

    `L.divIcon({ className: 'lt-pin', html: #{str(html)}, iconSize: [18, 18], iconAnchor: [9, 9] })`
  end

  # Frame the markers once, on the first render that has any. After that the
  # view is left alone so panning and zooming are not fought by new fixes --
  # the Recenter button is the way back.
  def fit_once
    return if @fitted

    return if markers.none? { |marker| placed?(marker) }

    @fitted = true
    recenter
  end

  def recenter
    return unless @map

    placed = markers.select { |marker| placed?(marker) }
    return if placed.empty?

    if placed.length == 1
      `#{@map}.setView(#{latlng(placed.first)}, #{SOLO_ZOOM})`
    else
      bounds = placed.map { |marker| latlng(marker) }
      `#{@map}.fitBounds(#{bounds}, { padding: [50, 50], maxZoom: #{SOLO_ZOOM} })`
    end
  end
end
