require_relative "test_helper"
require "kabosu/morpheme_list"
require "kabosu/pos_matcher"

# Lightweight stand-in for Kabosu::Morpheme without needing the Rust extension
MockMorpheme = Struct.new(:surface, :part_of_speech, keyword_init: true) unless defined?(MockMorpheme)

class PosMatcherTest < Minitest::Test
  def setup
    @noun_pos       = %w[名詞 普通名詞 一般 * * *]
    @proper_noun_pos = %w[名詞 固有名詞 地名 一般 * *]
    @verb_pos       = %w[動詞 一般 * * * *]
    @particle_pos   = %w[助詞 格助詞 * * * *]
    @adjective_pos  = %w[形容詞 一般 * * * *]
    @adverb_pos     = %w[副詞 * * * * *]
    @aux_verb_pos   = %w[助動詞 * * * * *]

    @tokyo = MockMorpheme.new(surface: "東京", part_of_speech: @proper_noun_pos)
    @miyako = MockMorpheme.new(surface: "都",  part_of_speech: @noun_pos)
    @ni    = MockMorpheme.new(surface: "に",   part_of_speech: @particle_pos)
    @iku   = MockMorpheme.new(surface: "行く", part_of_speech: @verb_pos)

    @morphemes = [@tokyo, @miyako, @ni, @iku]
  end

  # ── Construction ──

  def test_construct_from_block
    matcher = Kabosu::PosMatcher.new { |pos| pos[0] == "名詞" }
    assert matcher.match?(@noun_pos)
    refute matcher.match?(@verb_pos)
  end

  def test_construct_from_single_pattern
    matcher = Kabosu::PosMatcher.new(["名詞"])
    assert matcher.match?(@noun_pos)
    assert matcher.match?(@proper_noun_pos)
    refute matcher.match?(@verb_pos)
  end

  def test_construct_from_multiple_patterns
    matcher = Kabosu::PosMatcher.new(["名詞", "固有名詞"], ["動詞"])
    assert matcher.match?(@proper_noun_pos)
    assert matcher.match?(@verb_pos)
    refute matcher.match?(@noun_pos)  # 普通名詞, not 固有名詞
    refute matcher.match?(@particle_pos)
  end

  def test_construct_raises_with_both_patterns_and_block
    assert_raises(ArgumentError) do
      Kabosu::PosMatcher.new(["名詞"]) { |pos| pos[0] == "名詞" }
    end
  end

  def test_construct_raises_with_no_arguments
    assert_raises(ArgumentError) do
      Kabosu::PosMatcher.new
    end
  end

  # ── Wildcard matching ──

  def test_star_wildcard_matches_anything
    matcher = Kabosu::PosMatcher.new(["名詞", "*", "地名"])
    assert matcher.match?(@proper_noun_pos)
    refute matcher.match?(@noun_pos)
  end

  def test_nil_wildcard_matches_anything
    matcher = Kabosu::PosMatcher.new(["名詞", nil, "地名"])
    assert matcher.match?(@proper_noun_pos)
    refute matcher.match?(@noun_pos)
  end

  def test_partial_pattern_matches_prefix
    matcher = Kabosu::PosMatcher.new(["名詞"])
    assert matcher.match?(%w[名詞 固有名詞 地名 一般 * *])
    assert matcher.match?(%w[名詞 普通名詞 一般 * * *])
  end

  # ── match? with morpheme objects ──

  def test_match_with_morpheme_object
    matcher = Kabosu::PosMatcher.new(["名詞", "固有名詞"])
    assert matcher.match?(@tokyo)
    refute matcher.match?(@ni)
  end

  def test_match_raises_for_invalid_input
    matcher = Kabosu::PosMatcher.new(["名詞"])
    assert_raises(ArgumentError) { matcher.match?("not a morpheme") }
  end

  # ── filter & reject ──

  def test_filter_returns_matching_morphemes
    matcher = Kabosu::PosMatcher.new(["名詞"])
    result = matcher.filter(@morphemes)
    assert_equal %w[東京 都], result.map(&:surface)
  end

  def test_reject_returns_non_matching_morphemes
    matcher = Kabosu::PosMatcher.new(["名詞"])
    result = matcher.reject(@morphemes)
    assert_equal %w[に 行く], result.map(&:surface)
  end

  def test_filter_with_morpheme_list
    list = Kabosu::MorphemeList.new(@morphemes)
    matcher = Kabosu::PosMatcher.new(["動詞"])
    result = matcher.filter(list)
    assert_equal %w[行く], result.map(&:surface)
  end

  def test_filter_empty_collection
    matcher = Kabosu::PosMatcher.new(["名詞"])
    assert_empty matcher.filter([])
  end

  # ── Set operations ──

  def test_union
    nouns = Kabosu::PosMatcher.new(["名詞"])
    verbs = Kabosu::PosMatcher.new(["動詞"])
    combined = nouns | verbs

    assert combined.match?(@noun_pos)
    assert combined.match?(@verb_pos)
    refute combined.match?(@particle_pos)
  end

  def test_intersection
    nouns = Kabosu::PosMatcher.new(["名詞"])
    proper = Kabosu::PosMatcher.new { |pos| pos[1] == "固有名詞" }
    combined = nouns & proper

    assert combined.match?(@proper_noun_pos)
    refute combined.match?(@noun_pos)  # 普通名詞
    refute combined.match?(@verb_pos)
  end

  def test_difference_with_operator
    nouns = Kabosu::PosMatcher.new(["名詞"])
    proper = Kabosu::PosMatcher.new(["名詞", "固有名詞"])
    combined = nouns - proper

    assert combined.match?(@noun_pos)
    refute combined.match?(@proper_noun_pos)
    refute combined.match?(@verb_pos)
  end

  def test_difference_method
    nouns = Kabosu::PosMatcher.new(["名詞"])
    proper = Kabosu::PosMatcher.new(["名詞", "固有名詞"])
    combined = nouns.difference(proper)

    assert combined.match?(@noun_pos)
    refute combined.match?(@proper_noun_pos)
  end

  def test_chained_set_operations
    nouns = Kabosu::PosMatcher.new(["名詞"])
    verbs = Kabosu::PosMatcher.new(["動詞"])
    particles = Kabosu::PosMatcher.new(["助詞"])
    combined = (nouns | verbs) - particles

    result = combined.filter(@morphemes)
    assert_equal %w[東京 都 行く], result.map(&:surface)
  end

  # ── Pre-built matchers ──

  def test_nouns_matcher
    assert Kabosu::PosMatcher.nouns.match?(@noun_pos)
    assert Kabosu::PosMatcher.nouns.match?(@proper_noun_pos)
    refute Kabosu::PosMatcher.nouns.match?(@verb_pos)
  end

  def test_verbs_matcher
    assert Kabosu::PosMatcher.verbs.match?(@verb_pos)
    refute Kabosu::PosMatcher.verbs.match?(@noun_pos)
  end

  def test_adjectives_matcher
    assert Kabosu::PosMatcher.adjectives.match?(@adjective_pos)
    refute Kabosu::PosMatcher.adjectives.match?(@noun_pos)
  end

  def test_particles_matcher
    assert Kabosu::PosMatcher.particles.match?(@particle_pos)
    refute Kabosu::PosMatcher.particles.match?(@noun_pos)
  end

  def test_auxiliary_verbs_matcher
    assert Kabosu::PosMatcher.auxiliary_verbs.match?(@aux_verb_pos)
    refute Kabosu::PosMatcher.auxiliary_verbs.match?(@verb_pos)
  end

  def test_adverbs_matcher
    assert Kabosu::PosMatcher.adverbs.match?(@adverb_pos)
    refute Kabosu::PosMatcher.adverbs.match?(@noun_pos)
  end

  def test_proper_nouns_matcher
    assert Kabosu::PosMatcher.proper_nouns.match?(@proper_noun_pos)
    refute Kabosu::PosMatcher.proper_nouns.match?(@noun_pos)  # 普通名詞
    refute Kabosu::PosMatcher.proper_nouns.match?(@verb_pos)
  end

  def test_prebuilt_matchers_are_frozen
    assert Kabosu::PosMatcher.nouns.frozen?
    assert Kabosu::PosMatcher.verbs.frozen?
    assert Kabosu::PosMatcher.proper_nouns.frozen?
  end

  def test_prebuilt_matchers_are_cached
    assert_same Kabosu::PosMatcher.nouns, Kabosu::PosMatcher.nouns
    assert_same Kabosu::PosMatcher.verbs, Kabosu::PosMatcher.verbs
  end

  # ── Edge cases ──

  def test_match_empty_pos_array
    matcher = Kabosu::PosMatcher.new(["名詞"])
    refute matcher.match?([])
  end

  def test_match_shorter_pos_than_pattern
    matcher = Kabosu::PosMatcher.new(["名詞", "固有名詞", "地名"])
    refute matcher.match?(%w[名詞 固有名詞])
  end

  def test_match_longer_pos_than_pattern
    matcher = Kabosu::PosMatcher.new(["名詞"])
    assert matcher.match?(%w[名詞 固有名詞 地名 一般])
  end

  def test_all_wildcards_matches_anything
    matcher = Kabosu::PosMatcher.new(["*", "*"])
    assert matcher.match?(@noun_pos)
    assert matcher.match?(@verb_pos)
  end

  def test_block_with_nil_element
    matcher = Kabosu::PosMatcher.new { |pos| pos[0] == "名詞" }
    refute matcher.match?([nil, "固有名詞"])
  end
end
