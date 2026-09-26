# JSON endpoint behind the simulator's start/end address boxes:
#   GET /route?from=...&to=...
class RoutesController < ApplicationController
  # Each uncached lookup spends a share of free public services (see
  # RoutePlanner), so one visitor cannot hammer them.
  rate_limit to: 10, within: 1.minute,
             with: -> { render json: { error: "Too many route lookups -- wait a minute and try again." }, status: :too_many_requests }

  def show
    render json: RoutePlanner.plan(params[:from].to_s, params[:to].to_s)
  rescue RoutePlanner::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
