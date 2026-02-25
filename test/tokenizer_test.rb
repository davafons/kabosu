require_relative "test_helper"
require "kabosu"

class TokenizerTest < Minitest::Test
  include RequiresDictionary

  def setup
    super
    @dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
    @tok_c = @dict.create(mode: :c)
    @tok_a = @dict.create(mode: :a)
  end

  def with_stubbed_singleton_method(receiver, method_name, replacement)
    singleton = class << receiver
      self
    end
    original = receiver.method(method_name)
    begin
      singleton.send(:remove_method, method_name)
    rescue NameError
      nil
    end
    singleton.define_method(method_name, &replacement)
    begin
      yield
    ensure
      begin
        singleton.send(:remove_method, method_name)
      rescue NameError
        nil
      end
      singleton.define_method(method_name, original)
    end
  end

  # ── Creation ──

  def test_create_returns_tokenizer
    assert_instance_of Kabosu::Tokenizer, @tok_c
  end

  # ── tokenize returns MorphemeList ──

  def test_tokenize_returns_morpheme_list
    assert_instance_of Kabosu::MorphemeList, @tok_c.tokenize("東京")
  end

  def test_tokenize_morpheme_list_is_lazy
    list = @tok_c.tokenize("東京都に住んでいる")
    cache = list.instance_variable_get(:@morphemes)
    assert cache.all?(&:nil?), "expected lazy cache to be empty before first access"

    list.surfaces
    assert cache.all?(&:nil?), "surfaces should not force morpheme hydration"

    first = list[0]
    assert_instance_of Kabosu::Morpheme, first
    assert_same first, list[0], "expected morphemes to be memoized per index"
  end

  def test_tokenize_rejects_non_string_input
    assert_raises(ArgumentError) { @tok_c.tokenize(123) }
  end

  def test_tokenize_wraps_runtime_errors
    replacement = ->(_text) { raise RuntimeError, "native tokenize failure" }
    with_stubbed_singleton_method(@tok_c, :_tokenize, replacement) do
      error = assert_raises(Kabosu::TokenizationError) { @tok_c.tokenize("東京") }
      assert_match(/native tokenize failure/, error.message)
    end
  end

  # ── Surface faithfully reconstructs input ──

  def test_surfaces_reconstruct_input
    input = "東京都に住んでいる"
    result = @tok_c.tokenize(input)
    assert_equal input, result.surfaces.join
  end

  # ── Multiple sequential tokenize calls (buffer reuse) ──

  def test_multiple_sequential_tokenize_calls
    inputs = ["東京都に住んでいる", "大阪も好きだ", "食べました"]
    inputs.each do |input|
      result = @tok_c.tokenize(input)
      assert_equal input, result.surfaces.join,
        "Failed to reconstruct '#{input}' on sequential call"
    end
  end

  def test_repeated_tokenize_returns_consistent_results
    input = "東京都に住んでいる"
    result1 = @tok_c.tokenize(input)
    result2 = @tok_c.tokenize(input)
    assert_equal result1.surfaces, result2.surfaces
  end

  def test_shared_tokenizer_is_safe_across_threads
    threads = 8
    iterations = 200
    inputs = ["東京都に住んでいる", "大阪も好きだ", "食べました", "吾輩は猫である。"]
    failures = Queue.new

    workers = Array.new(threads) do |tid|
      Thread.new do
        iterations.times do |i|
          text = inputs[(tid + i) % inputs.length]
          surfaces = @tok_c.tokenize(text).surfaces.join
          failures << "mismatch for #{text.inspect}: got #{surfaces.inspect}" unless surfaces == text
        rescue StandardError => e
          failures << "#{e.class}: #{e.message}"
        end
      end
    end
    workers.each(&:join)

    assert failures.empty?, failures.size.times.map { failures.pop }.join("\n")
  end

  # ── mode ──

  def test_mode_returns_string
    assert_equal "C", @tok_c.mode
    assert_equal "A", @tok_a.mode
  end

  def test_invalid_mode_raises_argument_error
    assert_raises(ArgumentError) { @dict.create(mode: :x) }
    assert_raises(ArgumentError) { @dict.create(mode: "A") }
  end

  def test_fields_can_be_set_and_read
    tok = @dict.create(mode: :c, fields: %i[surface pos_id])
    assert_includes tok.fields, "surface"
    assert_includes tok.fields, "pos_id"
    refute_includes tok.fields, "reading_form"
    assert_raises(NoMethodError) { tok.fields = %i[surface pos_id reading_form] }
  end

  def test_create_rejects_unknown_keywords
    assert_raises(ArgumentError) { @dict.create(mode: :c, foo: true) }
  end

  def test_create_projection_is_reserved
    assert_raises(NotImplementedError) { @dict.create(mode: :c, projection: :surface) }
  end

  def test_oov_forms_do_not_raise_and_fall_back_to_surface
    input = "zzz"
    list = @tok_c.tokenize(input)

    assert_equal [input], list.surfaces
    assert_equal [input], list.readings
    assert_equal [input], list.dictionary_forms
    assert_equal [input], list.normalized_forms
  end

  # ── debug? (immutable, set at creation) ──

  def test_debug_defaults_to_false
    refute @tok_c.debug?
  end

  def test_debug_can_be_set_only_at_creation
    tok = @dict.create(mode: :c, debug: true)
    assert tok.debug?
    assert_raises(NoMethodError) { tok.debug = false }
  end

  # ── internal_cost ──

  def test_internal_cost_returns_integer
    @tok_c.tokenize("東京都に住んでいる")
    assert_kind_of Integer, @tok_c.internal_cost
  end

  # ── Kabosu.split_sentences ──

  def test_split_sentences_returns_array_of_strings
    result = Kabosu.split_sentences("東京都に住んでいる。大阪も好きだ。")
    assert_instance_of Array, result
    assert_operator result.size, :>=, 2
    result.each do |s|
      assert_instance_of String, s
    end
  end

  def test_split_sentences_preserves_full_text
    input = "東京都に住んでいる。大阪も好きだ。"
    result = Kabosu.split_sentences(input)
    assert_equal input, result.join
  end

  def test_split_sentences_single_sentence
    input = "東京都に住んでいる"
    result = Kabosu.split_sentences(input)
    assert_equal 1, result.size
    assert_equal input, result.first
  end

  def test_split_sentences_with_ranges
    input = "東京都に住んでいる。大阪も好きだ。"
    result = Kabosu.split_sentences(input, ranges: true)
    assert_operator result.size, :>=, 2
    assert result.all? { _1.is_a?(Kabosu::SentenceRange) }

    rebuilt = result.map(&:text).join
    assert_equal input, rebuilt
  end

  def test_split_sentences_with_limit
    input = "これはとても長い文ですそして読点も句点もありません"
    result = Kabosu.split_sentences(input, limit: 12)
    assert_equal input, result.join
  end

  def test_split_sentences_with_checker
    input = "株式会社テスト。東京都に住んでいる。"
    result = Kabosu.split_sentences(input, with_checker: true)
    assert_equal input, result.join
  end

  def test_split_sentences_is_safe_across_threads
    threads = 8
    iterations = 100
    input = "東京都に住んでいる。大阪も好きだ。"
    failures = Queue.new

    workers = Array.new(threads) do
      Thread.new do
        iterations.times do
          result = Kabosu.split_sentences(input).join
          failures << "mismatch: got #{result.inspect}" unless result == input
        rescue StandardError => e
          failures << "#{e.class}: #{e.message}"
        end
      end
    end
    workers.each(&:join)

    assert failures.empty?, failures.size.times.map { failures.pop }.join("\n")
  end

  def test_split_sentences_validates_keyword_types
    assert_raises(ArgumentError) { Kabosu.split_sentences(123) }
    assert_raises(ArgumentError) { Kabosu.split_sentences("東京", limit: "12") }
    assert_raises(ArgumentError) { Kabosu.split_sentences("東京", limit: 0) }
    assert_raises(ArgumentError) { Kabosu.split_sentences("東京", with_checker: "yes") }
    assert_raises(ArgumentError) { Kabosu.split_sentences("東京", ranges: "yes") }
    assert_raises(ArgumentError) { Kabosu.split_sentences("東京", dictionary: 123) }
  end

  def test_split_sentences_wraps_runtime_errors
    replacement = ->(_text, _limit, _dict_path) { raise RuntimeError, "native split failure" }
    with_stubbed_singleton_method(Kabosu, :_split_sentences, replacement) do
      error = assert_raises(Kabosu::SentenceSplitError) { Kabosu.split_sentences("東京。") }
      assert_match(/native split failure/, error.message)
    end
  end
end
