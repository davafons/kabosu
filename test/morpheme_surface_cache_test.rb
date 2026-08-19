require_relative "test_helper"
require "kabosu"

# `Morpheme#surface` hands back one frozen Ruby String per morpheme instead of
# building a new one per call: callers ask for it many times over (measured on a
# real tokenizer workload at 16.5 calls per morpheme, so 94% of the Strings it
# used to build were duplicates of one already made).
#
# Two things about that are load-bearing and neither is visible from Ruby, which
# is why they are pinned here rather than left to the caller to discover.
class MorphemeSurfaceCacheTest < Minitest::Test
  include RequiresDictionary

  SENTENCE = "これはテストです。すもももももももものうち。今日は６月１８日で、ムーリエルの誕生日です！".freeze

  def setup
    super
    @dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
    @tokenizer = @dict.create(mode: :c)
  end

  def test_the_same_morpheme_returns_the_same_object
    morpheme = @tokenizer.tokenize(SENTENCE).first

    assert_same morpheme.surface, morpheme.surface,
      "each call rebuilt the String, so the cache is not being used"
  end

  def test_the_cached_surface_is_frozen_so_the_mutable_copy_idiom_still_works
    morpheme = @tokenizer.tokenize(SENTENCE).first
    original = morpheme.surface.dup

    assert_predicate morpheme.surface, :frozen?

    # `+str` returns SELF for a mutable String and a mutable COPY for a frozen
    # one. Were the cached String mutable, this everyday idiom would append
    # straight into the cache and corrupt every later read of it.
    buffer = +morpheme.surface
    buffer << "テスト"

    assert_equal original, morpheme.surface, "writing through a `+str` copy reached the cache"
  end

  def test_cached_surfaces_survive_gc_stress_and_compaction
    morphemes = @tokenizer.tokenize(SENTENCE).to_a
    expected = morphemes.map { |morpheme| morpheme.surface.dup }

    # The cached String is reachable only from Rust, so it stays alive solely
    # because RbMorpheme marks it. Without that mark this collects the String out
    # from under the cache, and the failure is a crash or garbage rather than a
    # wrong answer: run it hard enough to catch that here rather than in a job.
    begin
      GC.stress = true
      5.times { morphemes.each(&:surface) }
    ensure
      GC.stress = false
    end
    GC.compact if GC.respond_to?(:compact)
    2.times { GC.start(full_mark: true, immediate_sweep: true) }

    assert_equal expected, morphemes.map(&:surface)
    assert_equal SENTENCE, morphemes.map(&:surface).join
  end
end
