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

    return if subscribed_cable_connections >= count

    raise <<~MESSAGE
      expected at least #{count} subscribed ActionCable connection(s) within #{timeout}s,
      saw #{subscribed_cable_connections} (open connections: #{ActionCable.server.connections.size})

      allowed_request_origins: #{Rails.application.config.action_cable.allowed_request_origins.inspect}
      disable_request_forgery_protection: #{Rails.application.config.action_cable.disable_request_forgery_protection.inspect}
      Capybara app host: #{Capybara.current_session.server&.base_url.inspect}

      browser console:
      #{browser_console_dump}
    MESSAGE
  end

  def browser_console_dump
    page.driver.browser.logs.get(:browser)
        .reject { |entry| entry.level == "INFO" }
        .last(15)
        .map { |entry| "  [#{entry.level}] #{entry.message[0, 300]}" }
        .join("\n")
  rescue StandardError => e
    "  (unavailable: #{e.class})"
  end
end

RSpec.configure do |config|
  config.include CableHelpers, type: :system
end
