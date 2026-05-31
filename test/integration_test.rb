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
    @dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
    @tok_c = @dict.create(mode: :c)
    @tok_a = @dict.create(mode: :a)
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

  def test_morpheme_split_preserves_original_offsets
    parent = @tok_c.tokenize("東京都に住んでいる").first
    split = parent.split(mode: :a)
    refute_empty split

    assert_equal parent.begin, split.first.begin
    assert_equal parent.end, split.last.end
    assert_equal parent.begin_c, split.first.begin_c
    assert_equal parent.end_c, split.last.end_c
  end

  def test_morpheme_split_invalid_mode_raises
    m = @tok_c.tokenize("東京").first
    assert_raises(ArgumentError) { m.split(mode: :x) }
    assert_raises(ArgumentError) { m.split(mode: "A") }
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

  def test_word_info_additional_fields_have_expected_types
    m = @tok_c.tokenize("東京都").first

    assert_kind_of Integer, m.dictionary_form_word_id
    assert_kind_of Integer, m.head_word_length
    assert_kind_of Array, m.a_unit_split
    assert_kind_of Array, m.b_unit_split
    assert_kind_of Array, m.word_structure
    assert m.a_unit_split.all? { _1.is_a?(Integer) }
    assert m.b_unit_split.all? { _1.is_a?(Integer) }
    assert m.word_structure.all? { _1.is_a?(Integer) }
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
    result = Kabosu.tokenize("東京", tokenizer: @tok_c)
    assert_instance_of Kabosu::MorphemeList, result
  end

  def test_convenience_tokenize_mode_a_and_c_differ
    a = Kabosu.tokenize("東京都", tokenizer: @tok_a).size
    c = Kabosu.tokenize("東京都", tokenizer: @tok_c).size
    assert_operator a, :>, c
  end

  def test_convenience_tokenize_requires_explicit_tokenizer
    assert_raises(ArgumentError) { Kabosu.tokenize("東京", tokenizer: "not-a-tokenizer") }
    assert_raises(ArgumentError) { Kabosu.tokenize("東京") }
  end

  def test_convenience_tokenize_is_safe_across_threads_with_shared_tokenizer
    threads = 8
    iterations = 200
    inputs = ["東京都に住んでいる", "大阪も好きだ", "食べました", "吾輩は猫である。"]
    failures = Queue.new

    workers = Array.new(threads) do |tid|
      Thread.new do
        iterations.times do |i|
          text = inputs[(tid + i) % inputs.length]
          surfaces = Kabosu.tokenize(text, tokenizer: @tok_c).surfaces.join
          failures << "mismatch for #{text.inspect}: got #{surfaces.inspect}" unless surfaces == text
        rescue StandardError => e
          failures << "#{e.class}: #{e.message}"
        end
      end
    end
    workers.each(&:join)

    assert failures.empty?, failures.size.times.map { failures.pop }.join("\n")
  end

  # ── Dictionary.new ──

  def test_dictionary_new_no_args_raises
    assert_raises(ArgumentError) { Kabosu::Dictionary.new }
  end

  def test_dictionary_new_with_explicit_path
    path = Kabosu::Dictionary.path
    dict = Kabosu::Dictionary.new(system_dict: path)
    assert_instance_of Kabosu::Dictionary, dict
  end

  def test_dictionary_new_with_invalid_path_raises
    assert_raises(Kabosu::DictionaryError) { Kabosu::Dictionary.new(system_dict: "/nonexistent/system.dic") }
  end

  # ── Dictionary lookup ──

  def test_dictionary_lookup_returns_prefix_matches
    query = "東京都"
    matches = @dict.lookup(query)

    assert_instance_of Kabosu::MorphemeList, matches
    assert_operator matches.size, :>, 0
    assert matches.all? { _1.is_a?(Kabosu::Morpheme) }

    matches.each do |m|
      assert_equal 0, m.begin
      assert_operator m.end, :<=, query.bytesize
      assert query.start_with?(m.surface),
        "Expected '#{m.surface}' to be a prefix of '#{query}'"
      assert_equal m.surface.bytesize, m.end
    end
  end

  # ── group_morphemes (native Rust path) ──

  def test_group_morphemes_produces_fewer_groups_than_raw_morphemes
    tokens = @tok_c.tokenize("食べてみた")
    grouped = tokens.group_morphemes
    assert_operator grouped.size, :<, tokens.size,
      "group_morphemes must merge inflectional suffixes into fewer groups"
  end

  def test_group_morphemes_te_form_chain_absorbed
    # て + いる/ある/くる/etc. is the canonical jpdb feature — everything
    # should collapse into one group so the surface is "住んでいる", not
    # three separate morphemes.
    tokens = @tok_c.tokenize("住んでいる")
    grouped = tokens.group_morphemes
    surfaces = grouped.map { |g| g.map(&:surface).join }
    assert_includes surfaces, "住んでいる"
    refute_includes surfaces, "いる"
  end

  def test_group_morphemes_clause_boundary_not_absorbed
    # ながら is a clause boundary particle; the Rust code must NOT absorb it
    # into the preceding verb. Otherwise two independent clauses would be
    # presented as one clickable chip.
    tokens = @tok_c.tokenize("食べながら働く")
    grouped = tokens.group_morphemes
    surfaces = grouped.map { |g| g.map(&:surface).join }
    assert_includes surfaces, "ながら"
    assert_includes surfaces, "働く"
  end

  def test_group_morphemes_native_and_fallback_parity
    # The Rust path and Ruby fallback must produce identical grouping for any
    # input, otherwise consumers that materialize the list first will see
    # different behavior.
    inputs = ["食べた", "食べない", "食べます", "住んでいる", "食べながら働く", "食べてみた"]

    inputs.each do |text|
      native = @tok_c.tokenize(text).group_morphemes
      fallback = Kabosu::MorphemeList.new(@tok_c.tokenize(text).to_a).group_morphemes

      native_surfaces = native.map { |g| g.map(&:surface).join }
      fallback_surfaces = fallback.map { |g| g.map(&:surface).join }

      assert_equal native_surfaces, fallback_surfaces,
        "Native and fallback diverged for #{text.inspect}: native=#{native_surfaces.inspect} fallback=#{fallback_surfaces.inspect}"
    end
  end
end
