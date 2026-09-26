require "rails_helper"

# These drive a real headless Chrome against a real server, so they exercise
# the whole stack: Opal-compiled components, Leaflet, and HyperModel sync over
# ActionCable. Geolocation itself is replaced by the app's own "Simulate
# movement" mode -- a real GPS fix is not available (or repeatable) in CI.
RSpec.describe "Live tracking", type: :system do
  # "#7c3aed" -> "rgb(124, 58, 237)"
  def rgb_of(hex)
    parts = hex.delete("#").scan(/../).map { |pair| pair.to_i(16) }
    "rgb(#{parts.join(', ')})"
  end

  it "renders the tracking page with the map and an identity" do
    visit "/me"

    expect(page).to have_content("Track me")
    expect(page).to have_content(/You are \w+ \w+/)
    expect(page).to have_button("Start tracking")
    # Leaflet actually mounted and drew tiles, rather than leaving a blank div.
    expect(page).to have_css(".leaflet-container", wait: 30)
    expect(page).to have_css(".leaflet-tile-pane", wait: 30)
  end

  it "places a marker and records a position once movement is simulated" do
    visit "/me"
    expect(page).to have_css(".leaflet-container", wait: 30)

    click_button "Simulate movement"

    # A pin on the map is the user-visible proof.
    expect(page).to have_css(".lt-pin", wait: 30)
    expect(page).to have_content(/Simulated movement - \d+ fixes/, wait: 30)

    # ...and it reached the database through HyperModel, not just local state.
    expect { Tracker.live.any? }.to eventually_be_truthy
    tracker = Tracker.live.first
    # Somewhere on the simulated Oceanside -> Vista drive.
    expect(tracker.lat).to be_within(0.02).of(33.185)
    expect(tracker.lng).to be_within(0.03).of(-117.296)
    # Ground elevation along the route is 39-88 m.
    expect(tracker.altitude).to be_between(30, 100)
    expect(tracker.locations.last.altitude).to be_between(30, 100)
    expect(tracker.locations.count).to be >= 1

    # ...and it is shown in the readout.
    expect(page).to have_content(/Altitude\s*\d+ m/)
  end

  describe "choosing the simulated drive" do
    it "offers the default addresses and drives them without a lookup" do
      expect(RoutePlanner).not_to receive(:plan)

      visit "/me"
      expect(page).to have_field("Drive from", with: "3541 Paseo de Francisco, Oceanside, CA 92056", wait: 30)
      expect(page).to have_field("Drive to", with: "260 Cedar Rd, Vista, CA 92083")

      click_button "Simulate movement"
      expect(page).to have_content(/Simulated movement - \d+ fixes/, wait: 30)
    end

    it "plans and drives a route between addresses the user typed" do
      # Somewhere well away from the default drive, so the fix proves which
      # route was driven. Stubbed in this process, which also runs the app.
      route = { points: [ [ 40.7580, -73.9855, 20.0 ], [ 40.7590, -73.9845, 22.0 ] ],
                distance_m: 140, from_label: "Times Sq", to_label: "Bryant Park" }
      allow(RoutePlanner).to receive(:plan).and_return(route)

      visit "/me"
      expect(page).to have_css(".leaflet-container", wait: 30)
      fill_in "Drive from", with: "Times Square, New York"
      fill_in "Drive to", with: "Bryant Park, New York"
      click_button "Simulate movement"

      expect(page).to have_content(/Simulated movement - \d+ fixes/, wait: 30)
      expect(RoutePlanner).to have_received(:plan)
        .with("Times Square, New York", "Bryant Park, New York", from_point: nil, to_point: nil)
      expect { Tracker.live.any? }.to eventually_be_truthy
      expect(Tracker.live.first.lat).to be_within(0.01).of(40.758)
      # The boxes are locked while the drive is under way.
      expect(page).to have_field("Drive from", disabled: true)
    end

    it "suggests addresses as you type, and drives from the one picked" do
      allow(AddressSuggester).to receive(:suggest).and_return([
        { label: "Oceanside Pier, Oceanside, California", lat: 33.1943, lng: -117.3844 },
        { label: "Oceanside Pier Way, Oceanside, California", lat: 33.1953, lng: -117.3827 }
      ])
      allow(RoutePlanner).to receive(:plan).and_return(
        { points: [ [ 33.1943, -117.3844, 4.0 ], [ 33.1950, -117.3800, 6.0 ] ] }
      )

      visit "/me"
      expect(page).to have_css(".leaflet-container", wait: 30)
      fill_in "Drive from", with: "oceanside pi"

      expect(page).to have_css(".lt-suggestion", count: 2, wait: 30)
      # Ranked around the start of the default drive until there is a fix.
      expect(AddressSuggester).to have_received(:suggest).with("oceanside pi", near: [ 33.18215, -117.3075 ])

      find(".lt-suggestion", text: "Oceanside Pier Way").click
      expect(page).to have_field("Drive from", with: "Oceanside Pier Way, Oceanside, California")
      expect(page).to have_no_css(".lt-suggestion")

      click_button "Simulate movement"
      expect(page).to have_content(/Simulated movement - \d+ fixes/, wait: 30)
      # The picked place's coordinates went along, so it was not re-geocoded.
      expect(RoutePlanner).to have_received(:plan).with(
        "Oceanside Pier Way, Oceanside, California", "260 Cedar Rd, Vista, CA 92083",
        from_point: [ 33.1953, -117.3827 ], to_point: nil
      )
    end

    it "lets a suggestion be chosen from the keyboard" do
      allow(AddressSuggester).to receive(:suggest).and_return([
        { label: "Vista Village, Vista, California", lat: 33.2003, lng: -117.2425 },
        { label: "Vista Way, Oceanside, California", lat: 33.1810, lng: -117.3200 }
      ])

      visit "/me"
      expect(page).to have_css(".leaflet-container", wait: 30)
      box = find_field("Drive to")
      box.fill_in(with: "vista")
      expect(page).to have_css(".lt-suggestion", count: 2, wait: 30)

      box.send_keys(:down, :down, :enter)
      expect(page).to have_field("Drive to", with: "Vista Way, Oceanside, California")
    end

    it "shows why a route could not be planned" do
      allow(RoutePlanner).to receive(:plan).and_raise(RoutePlanner::Error, "Couldn't find \"Atlantis\".")

      visit "/me"
      expect(page).to have_css(".leaflet-container", wait: 30)
      fill_in "Drive from", with: "Atlantis"
      click_button "Simulate movement"

      expect(page).to have_content("Couldn't find \"Atlantis\".", wait: 30)
      expect(page).to have_button("Simulate movement")
      expect(page).to have_field("Drive from", disabled: false)
    end
  end

  it "tracks real GPS fixes that carry no altitude" do
    visit "/me"
    expect(page).to have_css(".leaflet-container", wait: 30)

    # Most desktops report altitude as null. Stub the Geolocation API with
    # such a fix: JS null must not reach Ruby as a non-nil object.
    execute_script(<<~JS)
      navigator.geolocation.watchPosition = function (success) {
        success({ coords: { latitude: 33.2, longitude: -117.3, accuracy: 20, altitude: null } });
        return 1;
      };
    JS
    click_button "Start tracking"

    expect(page).to have_content(/Live - \d+ fixes received/, wait: 30)
    expect(page).to have_content(/Altitude\s*--/)
    expect { Tracker.live.any? }.to eventually_be_truthy
    expect(Tracker.live.first.altitude).to be_nil
  end

  it "draws a trail as more fixes arrive" do
    visit "/me"
    expect(page).to have_css(".leaflet-container", wait: 30)
    click_button "Simulate movement"
    expect(page).to have_css(".lt-pin", wait: 30)

    # The polyline only gets a rendered path once it has two or more points.
    expect(page).to have_css("path.leaflet-interactive", wait: 40)
  end

  it "keeps the map panned onto the pin while the simulation drives" do
    visit "/me"
    expect(page).to have_css(".leaflet-container", wait: 30)
    click_button "Simulate movement"
    expect(page).to have_css(".lt-pin", wait: 30)

    # panTo moves the map pane; without following it would sit still after
    # the initial framing while the pin drove away.
    pane_offset = -> { evaluate_script("document.querySelector('.leaflet-map-pane').style.transform") }
    first = pane_offset.call
    expect { pane_offset.call != first }.to eventually_be_truthy
  end

  it "stops reporting when tracking is stopped" do
    visit "/me"
    expect(page).to have_css(".leaflet-container", wait: 30)
    click_button "Simulate movement"
    expect { Tracker.live.any? }.to eventually_be_truthy

    click_button "Stop simulation"

    expect { Tracker.live.none? }.to eventually_be_truthy
  end

  it "shows nobody on the everyone page before anyone tracks" do
    visit "/everyone"
    expect(page).to have_content("Everyone")
    expect(page).to have_content("0 tracking now", wait: 30)
    expect(page).to have_content("Nobody is tracking yet")
  end

  it "shows one browser's movement on another browser's everyone map in real time" do
    # Session A: an observer sitting on the everyone page.
    Capybara.using_session(:observer) do
      visit "/everyone"
      expect(page).to have_css(".leaflet-container", wait: 30)
      expect(page).to have_content("0 tracking now", wait: 30)
      # Only once the observer is actually subscribed can it receive the
      # mover's broadcast; see spec/support/cable_helpers.rb.
      wait_for_subscription
    end

    # Session B: a separate browser session, so a separate Tracker, that starts
    # moving.
    Capybara.using_session(:mover) do
      visit "/me"
      expect(page).to have_css(".leaflet-container", wait: 30)
      click_button "Simulate movement"
      expect(page).to have_css(".lt-pin", wait: 30)
    end

    expect(Tracker.count).to eq(2)

    # The observer never reloaded: this only passes if the update arrived over
    # ActionCable and re-rendered the component.
    Capybara.using_session(:observer) do
      expect(page).to have_content("1 tracking now", wait: 40)
      expect(page).to have_css(".lt-pin", wait: 40)
    end
  end

  it "paints another browser's marker with its real colour and name" do
    # Regression guard: a Tracker can reach the map before HyperModel has
    # loaded its columns, and name/colour then arrive as DummyValues that
    # render as empty strings. The map has to reconcile them once they load,
    # or the pin stays colourless and unlabelled.
    expected = nil

    Capybara.using_session(:painter) do
      visit "/me"
      expect(page).to have_css(".leaflet-container", wait: 30)
      click_button "Simulate movement"
      expect(page).to have_css(".lt-pin", wait: 30)
      expect { Tracker.live.any? }.to eventually_be_truthy
      expected = Tracker.live.first
    end

    Capybara.using_session(:watcher) do
      visit "/everyone"
      expect(page).to have_content("1 tracking now", wait: 40)

      pin = find(".lt-pin span", match: :first, wait: 40)
      # Chrome reports the style attribute with colours normalised to rgb().
      expect(pin[:style]).to include(rgb_of(expected.color))

      expect(page).to have_css(".leaflet-tooltip", text: expected.name, wait: 40)
    end
  end

  it "keeps each browser's identity distinct on the everyone roster" do
    mover_name = nil

    Capybara.using_session(:mover2) do
      visit "/me"
      expect(page).to have_css(".leaflet-container", wait: 30)
      click_button "Simulate movement"
      expect(page).to have_css(".lt-pin", wait: 30)
      mover_name = Tracker.live.first.name
    end

    Capybara.using_session(:observer2) do
      visit "/everyone"
      expect(page).to have_content("1 tracking now", wait: 40)
      # The observer sees the mover by name, and is not itself the mover.
      expect(page).to have_content(mover_name, wait: 40)
      # The roster carries the mover's altitude alongside the coordinates.
      expect(page).to have_content(/· \d+ m/, wait: 40)
      expect(page).not_to have_content("#{mover_name} (you)")
    end
  end
end
