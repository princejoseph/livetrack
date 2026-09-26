# JSON endpoint behind the address boxes' autocomplete:
#   GET /suggest?q=...&lat=...&lng=...
class SuggestionsController < ApplicationController
  # Typing sends a request per pause, so this is far looser than /route's
  # limit, but it still stops one visitor exhausting a shared free service.
  rate_limit to: 60, within: 1.minute, with: -> { render json: [], status: :too_many_requests }

  def index
    render json: AddressSuggester.suggest(params[:q], near: near)
  end

  private

  # Rank results around this point if the client sent a sane one.
  def near
    lat = Float(params[:lat], exception: false)
    lng = Float(params[:lng], exception: false)
    [ lat, lng ] if lat&.between?(-90, 90) && lng&.between?(-180, 180)
  end
end
