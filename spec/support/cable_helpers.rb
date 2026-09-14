# Helpers for specs that assert on real-time behaviour.
#
# A page auto-connects its transport on boot, but asynchronously. The
# prerendered footer opens a Hyperstack::Connection row carrying a session id
# ("in progress"); only once the browser acks via connect-to-transport is that
# replaced by a `session: nil` row, which is the marker the broadcast path
# uses to decide a channel is live. A server-side change before that point
# races the subscription and is simply missed -- the client has nothing to
# re-fetch from, so the observing page keeps its initial data forever.
#
# This is a harness race, not an app defect: a real user's socket connects in
# well under a second and then stays up. Same approach as parking_lot.
module CableHelpers
  DEFAULT_CHANNEL = "Hyperstack::Application"

  def subscribed?(channel = DEFAULT_CHANNEL)
    Hyperstack::Connection.exists?(channel: channel, session: nil)
  end

  def wait_for_subscription(channel = DEFAULT_CHANNEL, timeout: 30)
    deadline = Time.now + timeout
    sleep 0.1 while !subscribed?(channel) && Time.now < deadline
    return if subscribed?(channel)

    raise <<~MESSAGE
      no live #{channel} subscription within #{timeout}s.

      connection rows: #{Hyperstack::Connection.all.map { |c| [ c.channel, c.session ] }.inspect}
      open websockets: #{ActionCable.server.connections.size}
      tables present:  connections=#{Hyperstack::Connection.table_exists?}

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
