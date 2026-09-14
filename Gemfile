source "https://rubygems.org"

gem "rails", "~> 8.0.5"

# The original asset pipeline — Hyperstack/Opal compile through Sprockets.
# Rails 8 generates Propshaft by default and dropped the --asset-pipeline=sprockets
# option, so this app was generated with --skip-asset-pipeline and wires it here.
gem "sprockets-rails"

gem "sqlite3", ">= 2.1"

# Rails 8.0's ActiveSupport::JSON calls JSON.generate(.., quirks_mode: true),
# a keyword json 3.0 removed -> "unknown keyword: quirks_mode" from any
# to_json (which react_component uses to serialise props). Ruby 3.4 ships
# json 3.x as a default gem, so hold it on 2.x.
gem "json", "< 3.0"
gem "puma", ">= 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mswin mswin64 mingw x64_mingw jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Hyperstack — React-style components in Ruby.
# Pin ALL 8 gems to the same fork/branch: rails-hyperstack depends on
# hyper-model, hyper-router and hyper-operation, and if those are left to
# resolve from rubygems.org the published 1.0.alpha1.8 still has unguarded
# Rails-breaking calls (e.g. InternalMetadata.do_not_synchronize).
HYPERSTACK = { github: "princejoseph/hyperstack", branch: "rails-8-compatibility" }.freeze
gem "rails-hyperstack",  **HYPERSTACK, glob: "ruby/rails-hyperstack/*.gemspec"
gem "hyper-component",   **HYPERSTACK, glob: "ruby/hyper-component/*.gemspec"
gem "hyper-state",       **HYPERSTACK, glob: "ruby/hyper-state/*.gemspec"
gem "hyperstack-config", **HYPERSTACK, glob: "ruby/hyperstack-config/*.gemspec"
gem "hyper-store",       **HYPERSTACK, glob: "ruby/hyper-store/*.gemspec"
gem "hyper-model",       **HYPERSTACK, glob: "ruby/hyper-model/*.gemspec"
gem "hyper-router",      **HYPERSTACK, glob: "ruby/hyper-router/*.gemspec"
gem "hyper-operation",   **HYPERSTACK, glob: "ruby/hyper-operation/*.gemspec"
gem "react-rails", ">= 2.4.0", "< 3.0"
# react-rails 2.7.1 builds its prerender pool with ConnectionPool.new(options_hash),
# but connection_pool 3.0 made #initialize keyword-only -> ArgumentError at boot
# (React::ServerRendering.reset_pool runs from the railtie even when prerendering
# is off). activesupport only needs >= 2.2.5, so hold connection_pool on 2.x.
gem "connection_pool", "< 3.0"
# NOT opal-rails: 2.x hard-caps rails < 7.3, and 3.x replaced the Sprockets
# integration with an app/opal -> app/assets/builds build step, which is not
# what Hyperstack's `//= require hyperstack-loader` needs. opal-sprockets is
# the same Sprockets integration with no Rails dependency at all, so it works
# on Rails 8. See config/initializers/opal_sprockets.rb.
gem "opal-sprockets"

group :development, :test do
  gem "debug", platforms: %i[ mri mswin mswin64 mingw x64_mingw ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"

  # Mounts a single Hyperstack component in isolation for unit-level specs.
  # require: false -- Bundler.require would otherwise load it before RSpec
  # exists, raising "uninitialized constant
  # RSpec::Expectations::PositiveExpectationHandler".
  gem "hyper-spec", **HYPERSTACK, glob: "ruby/hyper-spec/*.gemspec", require: false
end

group :development do
  gem "web-console"
  gem "foreman"
end
