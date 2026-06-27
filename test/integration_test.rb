require_relative "test_helper"
require "kabosu"

# Exercises kabosu's own API behavior end-to-end against a real dictionary:
# split modes, Morpheme#split, the Kabosu.tokenize convenience wrapper,
# Dictionary.new / lookup, group_morphemes, and thread safety.
#
# Field-level correctness (that every surface, POS, reading, offset, etc. equals
# what raw sudachi.rs produces) is verified exhaustively in conformance_test.rb,
# so it is intentionally not re-asserted here.
class IntegrationTest < Minitest::Test
  include RequiresDictionary

  def setup
    super
    @dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
    @tok_c = @dict.create(mode: :c)
    @tok_a = @dict.create(mode: :a)
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
    assert(matches.all?(Kabosu::Morpheme))

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
    inputs = %w[食べた 食べない 食べます 住んでいる 食べながら働く 食べてみた]

    inputs.each do |text|
      native = @tok_c.tokenize(text).group_morphemes
      fallback = Kabosu::MorphemeList.new(@tok_c.tokenize(text).to_a).group_morphemes

      native_surfaces = native.map { |g| g.map(&:surface).join }
      fallback_surfaces = fallback.map { |g| g.map(&:surface).join }

      assert_equal native_surfaces, fallback_surfaces,
                   "Native and fallback diverged for #{text.inspect}: " \
                   "native=#{native_surfaces.inspect} fallback=#{fallback_surfaces.inspect}"
    end
  end
end
