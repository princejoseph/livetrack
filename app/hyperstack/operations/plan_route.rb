# Plans the simulator's drive between two addresses. A ServerOp: called from
# the browser as PlanRoute.run(...), executed on the server, where it wraps
# RoutePlanner (app/services, server-only).
#
# Expected failures -- an address that cannot be found, no road route, the
# per-visitor limit -- come back as { error: "..." } rather than a raised
# exception: ServerOp reports any exception as an HTTP 500 and logs it as a
# HYPERSTACK ERROR, which a mistyped address is not.
class PlanRoute < Hyperstack::ServerOp
  # Supplied by the server from the session (ApplicationController#acting_user),
  # never by the client; a ServerOp without it refuses remote calls.
  param :acting_user
  param :from, type: String
  param :to, type: String
  # [lat, lng] of an address picked from the autocomplete, or nil.
  param :from_point, default: nil, nils: true
  param :to_point, default: nil, nils: true

  # Each uncached lookup spends a share of free public services.
  LOOKUPS_PER_MINUTE = 10

  step do
    if VisitorThrottle.exceeded?(:plan_route, params.acting_user, LOOKUPS_PER_MINUTE)
      { error: "Too many route lookups -- wait a minute and try again." }
    else
      RoutePlanner.plan(params.from, params.to,
                        from_point: RoutePlanner.point(params.from_point),
                        to_point: RoutePlanner.point(params.to_point))
    end
  rescue RoutePlanner::Error => e
    { error: e.message }
  end
end
