# Helpers for specs that assert on real-time behaviour.
#
# A browser's ActionCable subscription is established asynchronously, some
# time after the page has rendered. A broadcast raised before that completes
# is simply missed: HyperModel has nothing to re-fetch from, so the observing
# page sits on its initial data forever. Locally the subscription wins the
# race; on a slower CI runner it does not, which showed up as only the
# observer-first real-time spec failing.
#
# This is a test-harness race, not an app defect -- a real user's socket
# connects in well under a second and then stays up -- so the specs wait for
# the subscription rather than the app being changed to paper over it.
module CableHelpers
  # Capybara's server runs in this process, so the connections are inspectable
  # directly.
  def subscribed_cable_connections
    ActionCable.server.connections.count do |connection|
      connection.subscriptions.identifiers.any?
    rescue StandardError
      false
    end
  end

  def wait_for_cable_subscriptions(count = 1, timeout: 30)
    deadline = Time.now + timeout
    sleep 0.1 while subscribed_cable_connections < count && Time.now < deadline

    if subscribed_cable_connections < count
      raise "expected at least #{count} subscribed ActionCable connection(s) " \
            "within #{timeout}s, saw #{subscribed_cable_connections}"
    end
  end
end

RSpec.configure do |config|
  config.include CableHelpers, type: :system
end
