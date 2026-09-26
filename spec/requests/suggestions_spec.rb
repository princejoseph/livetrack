require "rails_helper"

RSpec.describe "Address suggestions", type: :request do
  it "returns suggestions as JSON, ranked around a sane point" do
    allow(AddressSuggester).to receive(:suggest)
      .and_return([ { label: "Oceanside Pier, Oceanside, California", lat: 33.19, lng: -117.38 } ])

    get "/suggest", params: { q: "oceanside pi", lat: "33.18", lng: "-117.29" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first["label"]).to eq("Oceanside Pier, Oceanside, California")
    expect(AddressSuggester).to have_received(:suggest).with("oceanside pi", near: [ 33.18, -117.29 ])
  end

  it "ignores a nonsense ranking point" do
    allow(AddressSuggester).to receive(:suggest).and_return([])

    get "/suggest", params: { q: "pier", lat: "abc", lng: "500" }

    expect(AddressSuggester).to have_received(:suggest).with("pier", near: nil)
  end
end
