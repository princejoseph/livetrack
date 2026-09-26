# JSON endpoint behind the simulator's start/end address boxes:
#   GET /route?from=...&to=...
class RoutesController < ApplicationController
  # Each uncached lookup spends a share of free public services (see
  # RoutePlanner), so one visitor cannot hammer them.
  rate_limit to: 10, within: 1.minute,
             with: -> { render json: { error: "Too many route lookups -- wait a minute and try again." }, status: :too_many_requests }

  def show
    render json: RoutePlanner.plan(params[:from].to_s, params[:to].to_s,
                                   from_point: point(:from), to_point: point(:to))
  rescue RoutePlanner::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  # from_lat/from_lng (or to_...) are sent when that address was picked from
  # the autocomplete, which already knows where it is.
  def point(side)
    lat = Float(params[:"#{side}_lat"], exception: false)
    lng = Float(params[:"#{side}_lng"], exception: false)
    [ lat, lng ] if lat&.between?(-90, 90) && lng&.between?(-180, 180)
  end
end
