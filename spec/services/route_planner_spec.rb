require "rails_helper"

# The real services are never contacted: get_json is stubbed per endpoint.
RSpec.describe RoutePlanner do
  subject(:planner) { described_class.new }

  let(:start_hit)  { { "lat" => "33.18", "lon" => "-117.30", "display_name" => "Start, Oceanside" } }
  let(:finish_hit) { { "lat" => "33.19", "lon" => "-117.28", "display_name" => "Finish, Vista" } }
  let(:geometry)   { [ [ -117.30, 33.18 ], [ -117.30, 33.18 ], [ -117.29, 33.185 ], [ -117.28, 33.19 ] ] }
  let(:osrm)       { { "code" => "Ok", "routes" => [ { "distance" => 2500.4, "geometry" => { "coordinates" => geometry } } ] } }

  before do
    # The Nominatim throttle would otherwise add a real second per spec.
    stub_const("RoutePlanner::NOMINATIM_GAP", 0)
    allow(planner).to receive(:get_json) do |url, params|
      case url
      when RoutePlanner::NOMINATIM then params[:q] == "start" ? [ start_hit ] : [ finish_hit ]
      when /router/ then osrm
      when RoutePlanner::ELEVATION then { "elevation" => Array.new(params[:latitude].split(",").length, 50.0) }
      end
    end
  end

  it "geocodes both ends, routes between them, and attaches elevation" do
    result = planner.plan("start", "finish")

    # OSRM's [lng, lat] is flipped, and the duplicate vertex dropped.
    expect(result[:points]).to eq([
      [ 33.18, -117.30, 50.0 ], [ 33.185, -117.29, 50.0 ], [ 33.19, -117.28, 50.0 ]
    ])
    expect(result[:distance_m]).to eq(2500)
    expect(result[:from_label]).to eq("Start, Oceanside")
    expect(result[:to_label]).to eq("Finish, Vista")
  end

  it "explains an address it cannot find" do
    allow(planner).to receive(:get_json).with(RoutePlanner::NOMINATIM, anything).and_return([])
    expect { planner.plan("nowhere", "finish") }.to raise_error(RoutePlanner::Error, /Couldn't find "nowhere"/)
  end

  it "rejects a blank address without calling out" do
    expect { planner.plan(" ", "finish") }.to raise_error(RoutePlanner::Error, /both a start and an end/)
    expect(planner).not_to have_received(:get_json)
  end

  it "reports when there is no driving route" do
    osrm.replace("code" => "NoRoute", "routes" => [])
    expect { planner.plan("start", "finish") }.to raise_error(RoutePlanner::Error, /No driving route/)
  end

  it "refuses drives too long to simulate" do
    osrm["routes"][0]["distance"] = 250_000
    expect { planner.plan("start", "finish") }.to raise_error(RoutePlanner::Error, /too long/)
  end

  it "still returns a route when the elevation lookup fails" do
    allow(planner).to receive(:get_json).with(RoutePlanner::ELEVATION, anything)
                                        .and_raise(RoutePlanner::Error, "busy")
    expect(planner.plan("start", "finish")[:points].map(&:last)).to all(be_nil)
  end

  it "thins long routes to MAX_POINTS, keeping the destination" do
    long = Array.new(1000) { |i| [ -117.3 + (i * 0.0001), 33.18 ] }
    osrm["routes"][0]["geometry"]["coordinates"] = long

    points = planner.plan("start", "finish")[:points]
    expect(points.length).to be <= RoutePlanner::MAX_POINTS + 1
    expect(points.last[0..1]).to eq([ 33.18, (-117.3 + (999 * 0.0001)).round(5) ])
  end
end
