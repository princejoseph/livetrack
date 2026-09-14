# Access rules for HyperModel sync. Unlike the generated scaffold, these apply
# in every environment including production -- this app is meant to be
# deployed, and an unregulated policy would let any client write any row.
module Hyperstack
  class ApplicationPolicy
    # The map is public: anyone may open a socket and watch it.
    always_allow_connection

    # Broadcast every attribute of every public model. This is safe here
    # because no model carries a secret: the session -> tracker mapping lives
    # in Rails' encrypted session cookie, not in a column. Keep it that way --
    # anything added to these tables becomes world-readable.
    regulate_all_broadcasts { |policy| policy.send_all }

    # acting_user is the Tracker owned by the requesting session
    # (see ApplicationController#acting_user). A session may move its own
    # marker and append to its own trail, and nothing else.
    allow_change(Tracker, on: [:update]) { acting_user && acting_user.id == id }
    allow_change(Location, on: [:create]) { acting_user && acting_user.id == tracker_id }

    # Trackers are created server-side on first visit, and trail pruning runs
    # in an after_create callback -- neither is a client-initiated change, so
    # no create/destroy permission is granted to the client at all.
  end
end
