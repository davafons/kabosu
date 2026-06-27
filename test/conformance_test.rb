require_relative "test_helper"
require_relative "conformance/corpus_helper"
require "kabosu"
require "json"

# Conformance: kabosu must reproduce raw sudachi.rs byte-for-byte.
#
# The fixtures in test/conformance/fixtures/ are produced by a reference binary
# (test/conformance/reference) that links the EXACT same sudachi.rs tag the
# extension links and loads the same dictionary. This test runs the same corpus
# through kabosu and asserts every exposed field matches the reference. Because
# both sides call into the identical crate, any divergence is a bug in kabosu's
# binding layer rather than in sudachi.
#
# Regenerate the fixtures with: ruby -Ilib test/conformance/generate.rb
class ConformanceTest < Minitest::Test
  include RequiresDictionary

  FIXTURES_DIR = File.expand_path("conformance/fixtures", __dir__)
  META_PATH = File.join(FIXTURES_DIR, "meta.json")

  # Every field kabosu exposes, paired with the morpheme method that produces
  # it. Keys match the JSON the reference dumper emits.
  FIELD_READERS = {
    "surface" => :surface,
    "part_of_speech" => :part_of_speech,
    "part_of_speech_id" => :part_of_speech_id,
    "dictionary_form" => :dictionary_form,
    "normalized_form" => :normalized_form,
    "reading_form" => :reading_form,
    "oov" => :oov?,
    "dictionary_id" => :dictionary_id,
    "word_id" => :word_id,
    "system" => :system?,
    "user" => :user?,
    "begin" => :begin,
    "end" => :end,
    "begin_c" => :begin_c,
    "end_c" => :end_c,
    "total_cost" => :total_cost,
    "synonym_group_ids" => :synonym_group_ids,
    "dictionary_form_word_id" => :dictionary_form_word_id,
    "head_word_length" => :head_word_length,
    "a_unit_split" => :a_unit_split,
    "b_unit_split" => :b_unit_split,
    "word_structure" => :word_structure
  }.freeze

  def setup
    super
    skip "No reference fixtures. Run: ruby -Ilib test/conformance/generate.rb" unless File.exist?(META_PATH)

    @meta = JSON.parse(File.read(META_PATH))
    @entry = Kabosu::Dictionary.list.find { _1[:edition] == @meta["dict_edition"] }
    skip "Reference dict edition '#{@meta["dict_edition"]}' not installed" unless @entry

    if @entry[:version] != @meta["dict_version"]
      skip "Dictionary drift: fixtures=#{@meta["dict_version"]} installed=#{@entry[:version]}; regenerate fixtures"
    end
    if ConformanceCorpus.sha256 != @meta["corpus_sha256"]
      skip "Corpus changed since fixtures were generated; regenerate fixtures"
    end

    @dict = Kabosu::Dictionary.new(system_dict: @entry[:path])
  end

  def test_kabosu_matches_raw_sudachi_mode_a
    assert_conformance("A")
  end

  def test_kabosu_matches_raw_sudachi_mode_b
    assert_conformance("B")
  end

  def test_kabosu_matches_raw_sudachi_mode_c
    assert_conformance("C")
  end

  private

  # Reference records grouped by source line index, preserving token order.
  def reference_by_line(mode)
    path = File.join(FIXTURES_DIR, "reference_#{mode}.jsonl")
    by_line = Hash.new { |h, k| h[k] = [] }
    File.foreach(path) do |line|
      rec = JSON.parse(line)
      by_line[rec["line"]] << rec
    end
    by_line
  end

  def assert_conformance(mode)
    tokenizer = @dict.create(mode: mode.downcase.to_sym)
    expected_by_line = reference_by_line(mode)
    corpus = ConformanceCorpus.lines

    corpus.each_with_index do |input, line|
      morphemes = tokenizer.tokenize(input).to_a
      expected = expected_by_line[line]

      assert_equal expected.size, morphemes.size,
                   "mode #{mode} line #{line} (#{input.inspect}): morpheme count differs"

      morphemes.each_with_index do |m, index|
        ref = expected[index]
        FIELD_READERS.each do |field, reader|
          got = m.public_send(reader)
          want = ref[field]
          assert_equal want, got,
                       "mode #{mode} line #{line} (#{input.inspect}) morpheme #{index} " \
                       "(#{m.surface.inspect}): field #{field.inspect} differs"
        end
      end
    end
  end
end
