# A text box with search-as-you-type address suggestions (the
# SuggestAddresses ServerOp).
#
# The typed text stays authoritative: suggestions are an aid, and an address
# typed in full (a US house number Photon does not know, say) still works --
# the server geocodes it when the route is planned. Picking a suggestion
# fires :pick with its coordinates, so that end needs no geocoding at all.
class AddressInput < HyperComponent
  param :label
  param :value
  param :locked, default: false
  # [lat, lng] to rank suggestions around.
  param :near, default: nil

  fires :text_change # (text) on every edit
  fires :pick        # ({ "label" =>, "lat" =>, "lng" => }) when one is chosen

  DEBOUNCE   = 0.3 # seconds of quiet before asking the server
  MIN_LENGTH = 3

  before_mount do
    @suggestions = []
    @highlight   = -1
    @open        = false
    @focused     = false
    # Bumped on every edit and pick; a response for an older value is dropped,
    # so a slow reply cannot overwrite the list for what is typed now.
    @seq = 0
  end

  render do
    # Positioned so the list can hang below the box, over the map.
    DIV(style: { position: "relative", flex: "1 1 260px" }) do
      LABEL(style: {
              display: "flex", flexDirection: "column",
              gap: "0.25rem", fontSize: "0.85rem", color: "#6b7280"
            }) do
        SPAN { label }
        INPUT(
          type: :text, value: value, disabled: locked,
          autoComplete: "off", role: "combobox",
          "aria-autocomplete": "list", "aria-expanded": showing?.to_s,
          style: {
            # 1rem or larger: iOS Safari zooms the page into smaller inputs.
            fontSize: "1rem", padding: "0.55rem 0.7rem", color: "#111827",
            border: "1px solid #d1d5db", borderRadius: "10px",
            background: locked ? "#f3f4f6" : "#fff"
          }
        ).on(:change) { |event| typed(event.target.value) }
          .on(:key_down) { |event| key_down(event) }
          .on(:focus) { focused }
          .on(:blur) { blurred }
      end

      suggestion_list if showing?
    end
  end

  def showing?
    @open && !locked && @suggestions.any?
  end

  def suggestion_list
    UL(
      role: "listbox",
      style: {
        position: "absolute", top: "100%", left: 0, right: 0,
        # Above Leaflet's panes and controls (up to 1000) and the Recenter
        # button (1200).
        zIndex: 1300,
        margin: "4px 0 0", padding: "4px 0", listStyle: "none",
        background: "#fff", border: "1px solid #d1d5db", borderRadius: "10px",
        boxShadow: "0 6px 18px rgba(0,0,0,0.12)", maxHeight: "260px", overflowY: "auto"
      }
    ) do
      @suggestions.each_with_index do |suggestion, index|
        LI(
          key: "#{index}-#{suggestion['label']}", role: "option", class: "lt-suggestion",
          "aria-selected": (index == @highlight).to_s,
          style: {
            padding: "0.6rem 0.75rem", fontSize: "1rem", color: "#111827", cursor: "pointer",
            background: index == @highlight ? "#eef2ff" : "transparent"
          }
        ) { suggestion["label"] }
          # mouse_down, not click: it fires before the input's blur, and
          # prevent_default keeps the focus in the box.
          .on(:mouse_down) { |event| event.prevent_default; choose(suggestion) }
          .on(:mouse_enter) { mutate @highlight = index }
      end
    end
  end

  # --- behaviour --------------------------------------------------------------

  def typed(text)
    text_change!(text)
    @seq += 1
    @debounce.abort if @debounce
    @debounce = nil

    if text.strip.length < MIN_LENGTH
      mutate do
        @suggestions = []
        @open = false
      end
      return
    end

    seq = @seq
    @debounce = after(DEBOUNCE) { fetch_suggestions(text, seq) }
  end

  # Suggestions are best-effort: a failed request just means no list.
  def fetch_suggestions(text, seq)
    SuggestAddresses.run(query: text, near: near)
                    .then { |list| on_suggestions(list, seq) }
  end

  def on_suggestions(list, seq)
    return unless seq == @seq

    list = [] unless list.is_a?(Array)

    mutate do
      @suggestions = list
      @highlight   = -1
      @open        = @focused && list.any?
    end
  end

  def key_down(event)
    return unless showing?

    case event.key
    when "ArrowDown"
      event.prevent_default
      mutate @highlight = (@highlight + 1) % @suggestions.length
    when "ArrowUp"
      event.prevent_default
      mutate @highlight = @highlight <= 0 ? @suggestions.length - 1 : @highlight - 1
    when "Enter"
      return if @highlight.negative?

      event.prevent_default
      choose(@suggestions[@highlight])
    when "Escape"
      mutate @open = false
    end
  end

  def choose(suggestion)
    @seq += 1
    @debounce.abort if @debounce
    @debounce = nil
    mutate do
      @open        = false
      @suggestions = []
      @highlight   = -1
    end
    pick!(suggestion)
  end

  def focused
    @focused = true
    mutate @open = true if @suggestions.any?
  end

  # Closed a beat late: some mobile browsers blur the box before the tap on
  # a suggestion registers, which would otherwise remove it mid-tap.
  def blurred
    @focused = false
    after(0.2) { mutate @open = false unless @focused }
  end
end
