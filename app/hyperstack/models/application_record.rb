class ApplicationRecord < ActiveRecord::Base
  if RUBY_ENGINE == "opal"
    # HyperModel's client-side ActiveRecord::Base does not implement
    # primary_abstract_class (a Rails 7 addition) and it is not in its
    # SERVER_METHODS ignore-list either, so calling it on the client raises
    # "called class method missing" and the whole Opal bundle stops loading --
    # which silently leaves every component unmounted. abstract_class= is the
    # equivalent the client does implement.
    self.abstract_class = true
  else
    primary_abstract_class
  end

  # Allow remote access to all scopes, in *every* environment.
  #
  # The installer generates this line with `unless Hyperstack.env.production?`,
  # which breaks the app in production only: a scope declared without an
  # explicit `regulate:` option gets an auto-regulator whose block returns nil,
  # so its permission is inherited from the parent relation
  # (see __synchromesh_regulate_from_macro / __set_synchromesh_permission_granted).
  # With `:all` unregulated in production, `Tracker.live` inherits nothing and
  # the everyone map comes back empty with no error anywhere.
  #
  # Reads being fully public is the intended design here -- a shared map of
  # everyone's position. Write access is what is actually restricted, in
  # app/policies/hyperstack/application_policy.rb.
  ApplicationRecord.regulate_scope :all
end
