# Per-visitor rate limiting for ServerOps. Rails' controller-level
# `rate_limit` does not reach them: they all arrive through Hyperstack's own
# /hyperstack/execute_remote endpoint.
module VisitorThrottle
  # True once +visitor+ has made more than +limit+ calls named +name+ in the
  # current window. Counts live in Rails.cache (so with the test suite's
  # null store nothing is ever throttled).
  def self.exceeded?(name, visitor, limit, within: 1.minute)
    window = Time.now.to_i / within.to_i
    key = "throttle|#{name}|#{visitor&.id}|#{window}"
    Rails.cache.increment(key, 1, expires_in: within).to_i > limit
  end
end
