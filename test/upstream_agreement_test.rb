require_relative "test_helper"
require_relative "conformance/corpus_helper"
require "kabosu"

# Checks kabosu against upstream's OWN behaviour rather than against a copy of
# kabosu's mappings (which is what the conformance reference is). Every
# expectation here is either a sudachi.rs invariant or a value SudachiPy 0.7
# returns for the same dictionary.
class UpstreamAgreementTest < Minitest::Test
  include RequiresDictionary

  # Inputs whose normalized form differs from the original text in length, so a
  # split that ignores normalization cuts them in the wrong place.
  NORMALIZING_INPUTS = [
    "ｺﾝﾋﾟｭｰﾀｰｳｲﾙｽ", # half-width kana with voicing marks
    "ﾃﾞｼﾞﾀﾙｶﾒﾗ",
    "コンピュータ〜〜ウイルス", # prolonged-sound-mark run collapses to one ー
    "徳島（とくしま）県庁", # yomigana in brackets is dropped
    "ＡＢＣ株式会社" # full-width alphanumerics
  ].freeze

  SPAN = %i[surface begin end begin_c end_c word_id].freeze

  def setup
    @dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
    @c = @dict.create(mode: :c)
  end

  # sudachi.rs tokenizes in mode C and splits the chosen path, so tokenizing in
  # mode A/B and splitting mode-C morphemes must give the same morphemes.
  def test_splitting_mode_c_reproduces_mode_a_and_b
    inputs = ConformanceCorpus.lines + NORMALIZING_INPUTS

    %i[a b].each do |mode|
      direct = @dict.create(mode: mode)
      inputs.each do |text|
        want = direct.tokenize(text).map { |m| SPAN.map { m.public_send(_1) } }
        got = @c.tokenize(text).flat_map { |m| m.split(mode: mode).to_a }.map { |m| SPAN.map { m.public_send(_1) } }

        assert_equal want, got, "mode #{mode}: split disagrees with direct tokenization for #{text.inspect}"
      end
    end
  end

  # sudachi.rs 0.7 normalizes lookup queries with the input-text plugins.
  def test_lookup_normalizes_the_query
    assert_includes @dict.lookup("ｶﾎﾞｽ").map(&:dictionary_form), "カボス"
    assert_equal "ｶﾎﾞｽ", @dict.lookup("ｶﾎﾞｽ").last.surface

    full_width = @dict.lookup("ＡＢＣ").select { _1.surface == "ＡＢＣ" }
    refute_empty full_width
    full_width.each { assert_equal 3, _1.end_c }
  end

  # index_form_length: bytes of the normalized form, for OOV words too.
  def test_head_word_length_is_normalized_bytes_for_every_morpheme
    tokens = @c.tokenize("東京都でズィーガンボルトを見た").to_a
    oov = tokens.find(&:oov?)

    refute_nil oov
    assert_equal oov.surface.bytesize, oov.head_word_length
    assert_equal "東京都".bytesize, tokens.first.head_word_length
    assert_equal "abc".bytesize, @c.tokenize("ＡＢＣ").first.head_word_length
  end
end
