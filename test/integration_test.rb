require_relative "test_helper"
require "kabosu"

# These tests verify that our Ruby layer correctly represents what comes back
# from the Rust extension. Rather than comparing against the CLI (which calls
# the same library), we assert known linguistic properties of Japanese text.
# A correct Sudachi output must satisfy these properties regardless of
# dictionary version — if any assertion fails, our mapping is broken.
class IntegrationTest < Minitest::Test
  include RequiresDictionary

  def setup
    super
    @dict = Kabosu::Dictionary.new
    @tok_c = @dict.create("C")
    @tok_a = @dict.create("A")
  end

  # ── MorphemeList return type ──

  def test_tokenize_returns_morpheme_list
    assert_instance_of Kabosu::MorphemeList, @tok_c.tokenize("東京")
  end

  # ── Surface faithfully reconstructs input ──

  def test_surfaces_reconstruct_input
    input = "東京都に住んでいる"
    result = @tok_c.tokenize(input)
    assert_equal input, result.surfaces.join
  end

  def test_surfaces_reconstruct_input_mode_a
    input = "東京都に住んでいる"
    result = @tok_a.tokenize(input)
    assert_equal input, result.surfaces.join
  end

  # ── Split modes produce different granularities ──

  def test_mode_c_produces_fewer_morphemes_than_mode_a
    # 東京都 is one morpheme in C, two in A (東京 + 都)
    c = @tok_c.tokenize("東京都").size
    a = @tok_a.tokenize("東京都").size
    assert_operator a, :>, c
  end

  def test_mode_a_splits_compound_verb
    # 住んでいる: A splits into 住ん, で, いる
    a = @tok_a.tokenize("住んでいる").surfaces
    assert_operator a.size, :>=, 2
  end

  # ── Part of speech ──

  def test_part_of_speech_is_array_of_six_strings
    result = @tok_c.tokenize("東京")
    result.each do |m|
      pos = m.part_of_speech
      assert_instance_of Array, pos
      assert_equal 6, pos.size
      pos.each { assert_instance_of String, _1 }
    end
  end

  def test_tokyo_is_proper_noun
    m = @tok_c.tokenize("東京").first
    assert_equal "名詞",   m.part_of_speech[0]
    assert_equal "固有名詞", m.part_of_speech[1]
  end

  def test_particle_ni_is_joshi
    m = @tok_c.tokenize("東京に").last
    assert_equal "助詞", m.part_of_speech[0]
  end

  # ── Reading form is katakana ──

  def test_reading_form_is_katakana
    result = @tok_c.tokenize("東京都に住んでいる")
    result.reject { _1.oov? }.each do |m|
      # Katakana range: U+30A0–U+30FF, plus ー, ヴ
      assert_match(/\A[\u30A0-\u30FF]+\z/, m.reading_form,
                   "Expected katakana reading for '#{m.surface}', got '#{m.reading_form}'")
    end
  end

  # ── Dictionary form is the lemma ──

  def test_inflected_verb_dictionary_form
    # 食べました → dictionary form should be 食べる
    morphemes = @tok_c.tokenize("食べました")
    tabe = morphemes.find { _1.surface == "食べ" }
    assert tabe, "Expected to find 食べ morpheme"
    assert_equal "食べる", tabe.dictionary_form
  end

  def test_dictionary_form_for_uninflected_word_equals_surface
    m = @tok_c.tokenize("東京").first
    assert_equal m.surface, m.dictionary_form
  end

  # ── Normalized form ──

  def test_normalized_form_is_string
    @tok_c.tokenize("東京都").each do |m|
      assert_instance_of String, m.normalized_form
      refute_empty m.normalized_form
    end
  end

  # ── OOV detection ──

  def test_common_words_are_not_oov
    result = @tok_c.tokenize("東京都に住んでいる")
    assert result.none?(&:oov?), "Expected no OOV in a common sentence"
  end

  def test_gibberish_may_be_oov
    result = @tok_c.tokenize("zzz")
    # Not guaranteed, but gibberish ASCII should appear somewhere
    assert_equal "zzz", result.surfaces.join
  end

  # ── Byte offsets ──

  def test_begin_end_are_byte_offsets_into_original_input
    input = "東京都"
    result = @tok_c.tokenize(input)
    # begin of first morpheme is 0, end of last equals byte length of input
    assert_equal 0, result.first.begin
    assert_equal input.bytesize, result.last.end
  end

  def test_offsets_are_contiguous
    input = "東京都に住んでいる"
    result = @tok_c.tokenize(input)
    result.each_cons(2) do |a, b|
      assert_equal a.end, b.begin,
        "Gap between '#{a.surface}' (end=#{a.end}) and '#{b.surface}' (begin=#{b.begin})"
    end
  end

  # ── part_of_speech_id ──

  def test_part_of_speech_id_is_integer
    @tok_c.tokenize("東京").each do |m|
      assert_kind_of Integer, m.part_of_speech_id
    end
  end

  def test_part_of_speech_id_is_consistent_for_same_pos
    # Two tokens with the same POS string should share the same id
    result = @tok_c.tokenize("東京に大阪に")
    particles = result.select { _1.part_of_speech[0] == "助詞" }
    assert_operator particles.size, :>=, 2
    ids = particles.map(&:part_of_speech_id).uniq
    assert_equal 1, ids.size, "Same POS should have same id"
  end

  # ── Kabosu.tokenize convenience ──

  def test_convenience_tokenize_returns_morpheme_list
    result = Kabosu.tokenize("東京")
    assert_instance_of Kabosu::MorphemeList, result
  end

  def test_convenience_tokenize_mode_a_and_c_differ
    a = Kabosu.tokenize("東京都", mode: "A").size
    c = Kabosu.tokenize("東京都", mode: "C").size
    assert_operator a, :>, c
  end

  def test_convenience_tokenize_caches_by_mode
    t1 = Kabosu.tokenize("東京", mode: "A")
    t2 = Kabosu.tokenize("東京", mode: "A")
    # Result should be equal (same tokenizer reused)
    assert_equal t1.surfaces, t2.surfaces
  end

  # ── Dictionary.new ──

  def test_dictionary_new_no_args_auto_discovers
    dict = Kabosu::Dictionary.new
    assert_instance_of Kabosu::Dictionary, dict
  end

  def test_dictionary_new_with_explicit_path
    path = Kabosu.dict_path
    dict = Kabosu::Dictionary.new(dict: path)
    assert_instance_of Kabosu::Dictionary, dict
  end

  def test_dictionary_new_with_invalid_path_raises
    assert_raises(RuntimeError) { Kabosu::Dictionary.new(dict: "/nonexistent/system.dic") }
  end
end
