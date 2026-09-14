require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "capybara/rspec"
require "selenium-webdriver"

Rails.root.glob("spec/support/**/*.rb").sort.each { |f| require f }

ActiveRecord::Migration.maintain_test_schema!


# This machine's chromedriver on PATH is stale relative to the installed
# Chrome, and Selenium Manager trusts a PATH driver over downloading a
# matching one. bin/rspec resolves a good driver and passes it in here.
CHROMEDRIVER_PATH = ENV["CHROMEDRIVER_PATH"].presence

Capybara.register_driver :livetrack_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")
  # Pinned generously larger than the rendered page: Leaflet sizes itself from
  # its container, and anything that has to be scrolled into view first makes
  # marker assertions flaky.
  options.add_argument("--window-size=1400,1200")
  # Surfaces Opal/Hyperstack errors, which otherwise fail silently as a blank
  # component with no clue in the RSpec output.
  options.add_option("goog:loggingPrefs", { browser: "ALL" })

  kwargs = { browser: :chrome, options: options }
  kwargs[:service] = Selenium::WebDriver::Service.chrome(path: CHROMEDRIVER_PATH) if CHROMEDRIVER_PATH

  Capybara::Selenium::Driver.new(app, **kwargs)
end

Capybara.server = :puma, { Silent: true }
# The Opal bundle is compiled on the first request and the pages then wait on
# an ActionCable round trip, so the default 2s is far too tight.
Capybara.default_max_wait_time = 30

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # HyperModel sync happens over a real socket against a real server, so the
  # browser must see committed rows -- transactional fixtures would hide them.
  config.use_transactional_fixtures = false

  config.before(:each, type: :system) do
    driven_by :livetrack_chrome
  end

  # Hyperstack.on_server? is `defined?(Rails::Server)`, so it is false under
  # RSpec even though Capybara's in-process Puma *is* the server. Two things
  # then break, both silently:
  #
  #   1. ReactiveRecord::Broadcast#after_commit takes its `send_to_server`
  #      branch -- an HTTP round trip wrapped in `rescue nil` -- so no
  #      ActionCable broadcast is ever emitted.
  #   2. Hyperstack only auto-creates its connection/queued-message tables
  #      when on_server? is true. Those tables live outside migrations and so
  #      are absent from db/schema.rb, which means a *fresh* database has
  #      neither -- connect-to-transport 503s and no browser ever subscribes.
  #
  # (2) is invisible locally, where the tables survive in test.sqlite3 from
  # earlier runs, and only shows up on CI. Same approach as parking_lot.
  config.before(:suite) do
    def Hyperstack.on_server?
      true
    end
    Hyperstack::Connection.build_tables
  end

  config.before(:each) do
    Location.delete_all
    Tracker.delete_all
    # Clear transport state too, so a subscription wait cannot be satisfied by
    # a leftover row from the previous example's page.
    Hyperstack::ConnectionAdapter::ActiveRecord::QueuedMessage.delete_all
    Hyperstack::ConnectionAdapter::ActiveRecord::Connection.delete_all
  end
end
