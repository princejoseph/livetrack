# Polls a block until it becomes truthy, for asserting on state that arrives
# asynchronously (a HyperModel write landing in the database after the browser
# sends it over ActionCable).
RSpec::Matchers.define :eventually_be_truthy do
  supports_block_expectations

  # A local, not a constant: the matcher body is re-evaluated per example, and
  # a constant here would be redefined each time.
  timeout = 40

  match do |probe|
    deadline = Time.now + timeout
    loop do
      break true if probe.call
      break false if Time.now > deadline

      sleep 0.25
    end
  end

  failure_message { "expected the block to become truthy within #{timeout}s, but it did not" }
end
