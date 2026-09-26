require "rails_helper"

RSpec.describe SuggestAddresses do
  let(:visitor) { Tracker.create!(Tracker.generate_identity) }

  def suggest(**params)
    described_class.run(acting_user: visitor, query: "oceanside pi", **params).value
  end

  it "returns suggestions, ranked around a sane point" do
    list = [ { label: "Oceanside Pier, Oceanside, California", lat: 33.19, lng: -117.38 } ]
    allow(AddressSuggester).to receive(:suggest).and_return(list)

    expect(suggest(near: [ 33.18, -117.29 ])).to eq(list)
    expect(AddressSuggester).to have_received(:suggest).with("oceanside pi", near: [ 33.18, -117.29 ])
  end

  it "ignores a nonsense ranking point" do
    allow(AddressSuggester).to receive(:suggest).and_return([])

    suggest(near: [ "abc", 500 ])

    expect(AddressSuggester).to have_received(:suggest).with("oceanside pi", near: nil)
  end

  it "goes quiet, rather than failing, over the limit" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(AddressSuggester).to receive(:suggest).and_return([ { label: "x" } ])

    SuggestAddresses::LOOKUPS_PER_MINUTE.times { suggest }
    expect(suggest).to eq([])
  end
end
