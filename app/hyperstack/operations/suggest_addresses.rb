# Autocomplete suggestions for the simulator's address boxes. A ServerOp
# wrapping AddressSuggester (app/services, server-only). Best-effort like the
# suggester itself: over the limit is simply no suggestions.
class SuggestAddresses < Hyperstack::ServerOp
  param :acting_user
  param :query, type: String
  # [lat, lng] to rank results around, or nil.
  param :near, default: nil, nils: true

  # Typing sends one lookup per pause, so far looser than PlanRoute's limit.
  LOOKUPS_PER_MINUTE = 60

  step do
    if VisitorThrottle.exceeded?(:suggest_addresses, params.acting_user, LOOKUPS_PER_MINUTE)
      []
    else
      AddressSuggester.suggest(params.query, near: RoutePlanner.point(params.near))
    end
  end
end
