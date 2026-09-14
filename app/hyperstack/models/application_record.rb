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

  # allow remote access to all scopes - i.e. you can count or get a list of ids
  # for any scope or relationship
  ApplicationRecord.regulate_scope :all unless Hyperstack.env.production?
end
