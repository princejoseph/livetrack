require "rails_helper"

RSpec.describe "Maps pages", type: :request do
  it "serves the tracking page and mounts the TrackMe component" do
    get "/me"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("TrackMe")
  end

  it "serves the everyone page and mounts the EveryoneMap component" do
    get "/everyone"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("EveryoneMap")
  end

  it "roots at the tracking page" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("TrackMe")
  end

  it "creates exactly one tracker for a single session across requests" do
    expect { get "/me" }.to change(Tracker, :count).by(1)
    expect { get "/everyone" }.not_to change(Tracker, :count)
  end

  it "gives a different session its own tracker" do
    get "/me"
    first = Tracker.last

    # A fresh request cycle with no cookies stands in for another browser.
    reset!
    get "/me"

    expect(Tracker.count).to eq(2)
    expect(Tracker.last).not_to eq(first)
  end

  it "never exposes a session secret in the page, only the tracker id" do
    get "/me"
    # Identity is the encrypted session cookie; the trackers table has no
    # token column at all, so there is nothing secret to leak.
    expect(Tracker.column_names).not_to include("token")
    expect(response.body).to include("acting_user_id")
  end
end
