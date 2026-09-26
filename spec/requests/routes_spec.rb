require "rails_helper"

RSpec.describe "Route lookup", type: :request do
  it "returns the planned route as JSON" do
    route = { points: [ [ 33.1, -117.2, 40.0 ], [ 33.2, -117.3, 45.0 ] ], distance_m: 1500,
              from_label: "A", to_label: "B" }
    allow(RoutePlanner).to receive(:plan).with("A st", "B st").and_return(route)

    get "/route", params: { from: "A st", to: "B st" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["points"]).to eq([ [ 33.1, -117.2, 40.0 ], [ 33.2, -117.3, 45.0 ] ])
  end

  it "returns planner errors as a 422 with a message" do
    allow(RoutePlanner).to receive(:plan).and_raise(RoutePlanner::Error, "Couldn't find \"x\".")

    get "/route", params: { from: "x", to: "y" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("Couldn't find \"x\".")
  end
end
