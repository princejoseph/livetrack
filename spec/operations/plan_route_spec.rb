require "rails_helper"

# Run server-side here; the browser path (PlanRoute.run from TrackMe, over
# /hyperstack/execute_remote) is covered by spec/system/tracking_spec.rb.
RSpec.describe PlanRoute do
  let(:visitor) { Tracker.create!(Tracker.generate_identity) }

  def plan(**params)
    described_class.run(acting_user: visitor, from: "A st", to: "B st", **params).value
  end

  it "returns the planned route" do
    route = { points: [ [ 33.1, -117.2, 40.0 ], [ 33.2, -117.3, 45.0 ] ], distance_m: 1500 }
    allow(RoutePlanner).to receive(:plan).with("A st", "B st", from_point: nil, to_point: nil).and_return(route)

    expect(plan).to eq(route)
  end

  it "passes a picked suggestion's coordinates through, ignoring nonsense" do
    allow(RoutePlanner).to receive(:plan).and_return({ points: [] })

    plan(from_point: [ "33.19", "-117.38" ], to_point: [ 999, 1 ])

    expect(RoutePlanner).to have_received(:plan)
      .with("A st", "B st", from_point: [ 33.19, -117.38 ], to_point: nil)
  end

  it "returns expected failures as an error message, not an exception" do
    allow(RoutePlanner).to receive(:plan).and_raise(RoutePlanner::Error, "Couldn't find \"x\".")

    expect(plan).to eq({ error: "Couldn't find \"x\"." })
  end

  it "limits each visitor's lookups" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(RoutePlanner).to receive(:plan).and_return({ points: [] })

    PlanRoute::LOOKUPS_PER_MINUTE.times { plan }
    expect(plan).to eq({ error: "Too many route lookups -- wait a minute and try again." })
    expect(RoutePlanner).to have_received(:plan).exactly(PlanRoute::LOOKUPS_PER_MINUTE).times

    # ...per visitor: someone else is unaffected.
    other = Tracker.create!(Tracker.generate_identity)
    expect(described_class.run(acting_user: other, from: "A st", to: "B st").value).to eq({ points: [] })
  end
end
