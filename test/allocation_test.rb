require_relative "test_helper"
require_relative "allocation/measure"
require_relative "allocation/workloads"
require "kabosu"
require "yaml"

# Allocation ratchet, in two tiers.
#
# Tier 1 is an INVARIANT with no baseline behind it: a repeat ask for a cached
# field allocates nothing. That is the property the caches exist for; it is either
# true or it is not, and no recorded number should be needed to say so.
#
# Tier 2 is recorded numbers for whole workloads, gated against
# test/allocation/baselines.yml. Those are keyed by dictionary edition, because a
# `full` dictionary segments differently from `core` and their numbers are never
# comparable. A missing key is a SKIP, not a failure.
#
# Wall clock is deliberately absent and must never gate anything: on this workload
# it swung by 5x purely from page-cache warming, while the object counts below
# reproduce to the object.
#
# Identity, frozen-ness and GC survival of the cached values live in
# morpheme_surface_cache_test.rb and are not repeated here.
class AllocationTest < Minitest::Test
  include RequiresDictionary

  BASELINES = File.expand_path("allocation/baselines.yml", __dir__)

  def setup
    super
    @dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
    @toks = Allocation::Workloads.tokenizers(@dict)
  end

  # ── Tier 1: the invariant ─────────────────────────────────────────────

  def test_a_repeat_ask_for_a_cached_field_allocates_nothing
    morphemes = @toks[:c].tokenize(Allocation::Workloads::CORPUS.first).to_a
    morphemes.each { |m| m.surface; m.dictionary_form; m.part_of_speech } # fill

    # Through `stable`, not a bare `objects`: the FIRST measurement of any new
    # call site pays for warming it (a `public_send` site measured 3 objects once
    # and 0 every time after), and that warmup is not what this asserts.
    %i[surface dictionary_form part_of_speech].each do |field|
      allocated, stable = Allocation.stable { morphemes.each { |m| m.public_send(field) } }

      assert stable, "#{field} would not stabilise (#{allocated} objects): the environment cannot be measured"
      assert_equal 0, allocated,
        "#{field} allocated #{allocated} objects on a repeat ask: its cache is not being hit"
    end
  end

  # A field we deliberately do NOT cache, asserted so the decision is visible
  # rather than forgotten. reading_form measured 1.8 calls per morpheme, so a
  # cache would buy ~0.3% of allocations and cost a retained String per morpheme.
  # If this ever starts returning 0, someone cached it: check that trade first.
  def test_uncached_fields_are_a_recorded_decision_not_an_oversight
    morphemes = @toks[:c].tokenize(Allocation::Workloads::CORPUS.first).to_a
    morphemes.each(&:reading_form)
    allocated, = Allocation.stable { morphemes.each(&:reading_form) }

    assert_operator allocated, :>, 0,
      "reading_form now allocates nothing, so it has been cached: confirm the memory trade was measured"
  end

  # ── Tier 2: the recorded numbers ──────────────────────────────────────

  def test_workload_allocations_have_not_regressed
    skip "no baselines recorded yet: run `rake alloc:record`" unless File.exist?(BASELINES)

    recorded = YAML.load_file(BASELINES)
    edition = Kabosu::Dictionary.path.to_s[/small|core|full/] || "unknown"
    expected = recorded[edition]
    skip "no baseline for the #{edition} dictionary" if expected.nil?

    Allocation::Workloads.all.each do |name, body|
      want = expected[name]
      next if want.nil?

      got, stable = Allocation.stable { body.call(@toks) }
      # A measurement that will not repeat itself is not a measurement.
      skip "#{name} would not stabilise (#{got} objects)" unless stable

      # BOTH directions stop the build. Up is a regression; down is an
      # improvement nobody has locked in yet, so re-record and hold the new floor.
      assert_equal want, got,
        "#{name}: allocations moved #{want} -> #{got} (#{got > want ? 'REGRESSION' : 'improvement, re-record with `rake alloc:record`'})"
    end
  end
end
