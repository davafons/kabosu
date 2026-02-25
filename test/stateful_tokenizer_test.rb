require_relative "test_helper"
require "kabosu"

class StatefulTokenizerTest < Minitest::Test
  include RequiresDictionary

  def setup
    super
    @dict = Kabosu::Dictionary.new
    @stok_c = @dict.create_stateful("C")
    @stok_a = @dict.create_stateful("A")
    @tok_c = @dict.create("C")
    @tok_a = @dict.create("A")
  end

  # ── Creation ──

  def test_create_stateful_returns_stateful_tokenizer
    assert_instance_of Kabosu::StatefulTokenizer, @stok_c
  end

  # ── tokenize returns MorphemeList ──

  def test_tokenize_returns_morpheme_list
    assert_instance_of Kabosu::MorphemeList, @stok_c.tokenize("東京")
  end

  # ── Surface faithfully reconstructs input ──

  def test_surfaces_reconstruct_input
    input = "東京都に住んでいる"
    result = @stok_c.tokenize(input)
    assert_equal input, result.surfaces.join
  end

  # ── Results match StatelessTokenizer ──

  def test_results_match_stateless_tokenizer_mode_c
    input = "東京都に住んでいる"
    stateful_result = @stok_c.tokenize(input)
    stateless_result = @tok_c.tokenize(input)

    assert_equal stateless_result.surfaces, stateful_result.surfaces
    assert_equal stateless_result.map(&:reading_form), stateful_result.map(&:reading_form)
    assert_equal stateless_result.map(&:dictionary_form), stateful_result.map(&:dictionary_form)
    assert_equal stateless_result.map(&:part_of_speech), stateful_result.map(&:part_of_speech)
  end

  def test_results_match_stateless_tokenizer_mode_a
    input = "東京都に住んでいる"
    stateful_result = @stok_a.tokenize(input)
    stateless_result = @tok_a.tokenize(input)

    assert_equal stateless_result.surfaces, stateful_result.surfaces
  end

  # ── Multiple sequential tokenize calls (buffer reuse) ──

  def test_multiple_sequential_tokenize_calls
    inputs = ["東京都に住んでいる", "大阪も好きだ", "食べました"]
    inputs.each do |input|
      result = @stok_c.tokenize(input)
      assert_equal input, result.surfaces.join,
        "Failed to reconstruct '#{input}' on sequential call"
    end
  end

  def test_repeated_tokenize_returns_consistent_results
    input = "東京都に住んでいる"
    result1 = @stok_c.tokenize(input)
    result2 = @stok_c.tokenize(input)
    assert_equal result1.surfaces, result2.surfaces
  end

  # ── mode ──

  def test_mode_returns_string
    assert_equal "C", @stok_c.mode
    assert_equal "A", @stok_a.mode
  end

  # ── debug? ──

  def test_debug_defaults_to_false
    refute @stok_c.debug?
  end

  def test_debug_can_be_set
    @stok_c.debug = true
    assert @stok_c.debug?
    @stok_c.debug = false
    refute @stok_c.debug?
  end

  # ── internal_cost ──

  def test_internal_cost_returns_integer
    @stok_c.tokenize("東京都に住んでいる")
    assert_kind_of Integer, @stok_c.internal_cost
  end

  def test_internal_cost_matches_stateless
    input = "東京都に住んでいる"
    @stok_c.tokenize(input)
    @tok_c.tokenize(input)
    assert_equal @tok_c.internal_cost, @stok_c.internal_cost
  end

  # ── tokenize_sentences ──

  def test_tokenize_sentences_returns_array_of_morpheme_lists
    result = @stok_c.tokenize_sentences("東京都に住んでいる。大阪も好きだ。")
    assert_instance_of Array, result
    assert_operator result.size, :>=, 2
    result.each do |ml|
      assert_instance_of Kabosu::MorphemeList, ml
    end
  end

  # ── Kabosu.batch_tokenizer convenience ──

  def test_batch_tokenizer_returns_stateful_tokenizer
    tok = Kabosu.batch_tokenizer(mode: "A")
    assert_instance_of Kabosu::StatefulTokenizer, tok
  end

  def test_batch_tokenizer_works_for_batch_processing
    tok = Kabosu.batch_tokenizer(mode: "C")
    results = []
    ["東京都", "大阪府", "京都市"].each do |text|
      results << tok.tokenize(text)
    end
    assert_equal 3, results.size
    results.each { |r| assert_instance_of Kabosu::MorphemeList, r }
  end
end
