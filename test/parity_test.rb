require_relative "test_helper"
require_relative "conformance/corpus_helper"
require "kabosu"
require "json"

# Parity: how close are kabosu's bindings to the official SudachiPy bindings?
#
# SudachiPy is the official Python binding to the same sudachi.rs core kabosu
# wraps. The fixtures in test/parity/fixtures/ are produced by running SudachiPy
# (test/parity/dump_sudachipy.py) against the SAME dictionary, config, and
# resources kabosu uses. This test runs the same corpus through kabosu and
# asserts the two bindings return identical values for every field they share.
#
# Semantic note: SudachiPy's begin()/end() are CHARACTER offsets, which map to
# kabosu's begin_c/end_c. kabosu additionally exposes byte offsets (begin/end),
# system?/user?, and total_cost, and flattens WordInfo (head_word_length,
# a_unit_split, …) directly onto the morpheme rather than behind a separate
# get_word_info() object. Those API-surface differences are documented in
# test/parity/PARITY.md; this test verifies the OVERLAP agrees exactly.
#
# Regenerate the fixtures with:
#   test/parity/setup.sh && ruby -Ilib test/parity/generate.rb
class ParityTest < Minitest::Test
  include RequiresDictionary

  FIXTURES_DIR = File.expand_path("parity/fixtures", __dir__)
  META_PATH = File.join(FIXTURES_DIR, "meta.json")

  # Fields with identical meaning in both bindings: SudachiPy key => kabosu method.
  SHARED_FIELDS = {
    "surface" => :surface,
    "part_of_speech" => :part_of_speech,
    "part_of_speech_id" => :part_of_speech_id,
    "dictionary_form" => :dictionary_form,
    "normalized_form" => :normalized_form,
    "reading_form" => :reading_form,
    "oov" => :oov?,
    "dictionary_id" => :dictionary_id,
    "word_id" => :word_id,
    "synonym_group_ids" => :synonym_group_ids,
    # SudachiPy character offsets == kabosu character offsets.
    "begin_c" => :begin_c,
    "end_c" => :end_c
  }.freeze

  # WordInfo-derived fields. SudachiPy exposes these on a separate get_word_info()
  # object (and only for in-vocabulary tokens); kabosu exposes them on the
  # morpheme. Compared only where the fixture recorded them (non-OOV tokens).
  WORDINFO_FIELDS = {
    "head_word_length" => :head_word_length,
    "dictionary_form_word_id" => :dictionary_form_word_id,
    "a_unit_split" => :a_unit_split,
    "b_unit_split" => :b_unit_split,
    "word_structure" => :word_structure
  }.freeze

  def setup
    super
    unless File.exist?(META_PATH)
      skip "No SudachiPy fixtures. Run: test/parity/setup.sh && ruby -Ilib test/parity/generate.rb"
    end

    @meta = JSON.parse(File.read(META_PATH))
    @entry = Kabosu::Dictionary.list.find { _1[:edition] == @meta["dict_edition"] }
    skip "Parity dict edition '#{@meta["dict_edition"]}' not installed" unless @entry

    if @entry[:version] != @meta["dict_version"]
      skip "Dictionary drift: fixtures=#{@meta["dict_version"]} installed=#{@entry[:version]}; regenerate fixtures"
    end
    if ConformanceCorpus.sha256 != @meta["corpus_sha256"]
      skip "Corpus changed since fixtures were generated; regenerate fixtures"
    end

    @dict = Kabosu::Dictionary.new(system_dict: @entry[:path])
  end

  def test_kabosu_matches_sudachipy_mode_a
    assert_parity("A")
  end

  def test_kabosu_matches_sudachipy_mode_b
    assert_parity("B")
  end

  def test_kabosu_matches_sudachipy_mode_c
    assert_parity("C")
  end

  private

  def sudachipy_by_line(mode)
    path = File.join(FIXTURES_DIR, "sudachipy_#{mode}.jsonl")
    by_line = Hash.new { |h, k| h[k] = [] }
    File.foreach(path) do |line|
      rec = JSON.parse(line)
      by_line[rec["line"]] << rec
    end
    by_line
  end

  def assert_parity(mode)
    tokenizer = @dict.create(mode: mode.downcase.to_sym)
    expected_by_line = sudachipy_by_line(mode)
    corpus = ConformanceCorpus.lines

    corpus.each_with_index do |input, line|
      morphemes = tokenizer.tokenize(input).to_a
      expected = expected_by_line[line]

      assert_equal expected.size, morphemes.size,
                   "mode #{mode} line #{line} (#{input.inspect}): kabosu and SudachiPy disagree on morpheme count"

      morphemes.each_with_index do |m, index|
        ref = expected[index]
        fields = SHARED_FIELDS.dup
        WORDINFO_FIELDS.each { |k, v| fields[k] = v if ref.key?(k) }

        fields.each do |field, reader|
          assert_equal ref[field], m.public_send(reader),
                       "mode #{mode} line #{line} (#{input.inspect}) morpheme #{index} " \
                       "(#{m.surface.inspect}): field #{field.inspect} differs between kabosu and SudachiPy"
        end
      end
    end
  end
end
