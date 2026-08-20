# frozen_string_literal: true

# Objects allocated by a block, with the GC held off so nothing is recycled
# mid-measure and the count is of what was MADE, not what survived.
module Allocation
  module_function

  # `GC.stat(:symbol)` returns an Integer and builds nothing. The bare `GC.stat`
  # builds a Hash and would count itself: that is the trap this exists to avoid.
  def objects
    GC.start
    GC.disable
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  ensure
    GC.enable
  end

  # Which dictionary the numbers belong to. BOTH halves matter: `full` segments
  # differently from `core`, and so does the same edition at a different release,
  # so 20260116 and 20260428 are not comparable either. A key nobody recorded is a
  # skip, never a failure.
  def dictionary_key(path = Kabosu::Dictionary.path.to_s)
    edition = path[/small|core|full/] || "unknown"
    version = path[/sudachi-dictionary-(\d+)/, 1] || "unknown"
    "#{edition}-#{version}"
  end

  # Run it until it repeats itself. The first passes warm process-wide state (the
  # POS cache, inline caches, fstring dedup), so a reading only counts once the
  # same work twice in a row costs the same. `stable: false` means the environment
  # cannot be measured — a skip locally, a failure in CI, and never a number
  # anybody acts on.
  def stable(attempts: 6)
    last = nil
    attempts.times do
      current = objects { yield }
      return [ current, true ] if current == last

      last = current
    end
    [ last, false ]
  end
end
