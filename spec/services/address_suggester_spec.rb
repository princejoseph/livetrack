require "rails_helper"

# Photon itself is never contacted: fetch is stubbed.
RSpec.describe AddressSuggester do
  def feature(lat, lng, **props)
    { "geometry" => { "coordinates" => [ lng, lat ] }, "properties" => props.transform_keys(&:to_s) }
  end

  it "labels suggestions readably, dropping the country for the US and duplicates" do
    photon = { "features" => [
      feature(33.19, -117.38, name: "Oceanside Pier", city: "Oceanside", state: "California", countrycode: "US"),
      feature(33.19, -117.38, name: "Oceanside Pier", city: "Oceanside", state: "California", countrycode: "US"),
      feature(33.18, -117.30, housenumber: "260", street: "3rd Avenue", city: "Chula Vista",
                              state: "California", countrycode: "US"),
      feature(51.50, -0.12, name: "Pier Street", city: "London", country: "United Kingdom", countrycode: "GB")
    ] }
    allow_any_instance_of(described_class).to receive(:fetch).and_return(photon)

    expect(described_class.suggest("pier").map { |s| s[:label] }).to eq([
      "Oceanside Pier, Oceanside, California",
      "260 3rd Avenue, Chula Vista, California",
      "Pier Street, London, United Kingdom"
    ])
  end

  it "sends the ranking point, rounded" do
    suggester = described_class.new
    allow(described_class).to receive(:new).and_return(suggester)
    allow(suggester).to receive(:fetch).and_return({ "features" => [] })

    described_class.suggest("pier", near: [ 33.18215, -117.3075 ])

    expect(suggester).to have_received(:fetch).with(hash_including(q: "pier", lat: 33.2, lon: -117.3))
  end

  it "does not ask about queries too short to be useful" do
    expect(described_class).not_to receive(:new)
    expect(described_class.suggest(" ab ")).to eq([])
  end

  it "returns nothing, quietly, when Photon fails" do
    allow_any_instance_of(described_class).to receive(:fetch).and_return(nil)
    expect(described_class.suggest("pier")).to eq([])
  end
end
