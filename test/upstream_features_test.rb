require_relative "test_helper"
require "kabosu"

# The APIs sudachi.rs / SudachiPy 0.7 added, and V1 user dictionaries built
# with Kabosu.build_user_dict against whatever system dictionary is installed.
class UpstreamFeaturesTest < Minitest::Test
  include RequiresDictionary

  USER_CSV = File.expand_path("fixtures/user_dict.csv", __dir__)

  # Building takes seconds against a `full` dictionary, so it happens once per
  # run and per system dictionary.
  def self.user_dic_for(system)
    @user_dics ||= {}
    @user_dics[system] ||= begin
      dir = Dir.mktmpdir
      Minitest.after_run { FileUtils.rm_rf(dir) }
      Kabosu.build_user_dict(USER_CSV, output: File.join(dir, "user.dic"), system_dict: system)
    end
  end

  def setup
    @system = Kabosu::Dictionary.path
    @dict = Kabosu::Dictionary.new(system_dict: @system)
    @tok = @dict.create
  end

  # ── Form morphemes ──

  def test_dictionary_form_morpheme_is_the_lemma_entry
    m = @tok.tokenize("住んでいた").first
    lemma = m.dictionary_form_morpheme

    assert_equal %w[住ん 住む], [m.surface, lemma.surface]
    assert_equal "終止形-一般", lemma.part_of_speech.last
    assert_equal [0, 6, 0, 2], [lemma.begin, lemma.end, lemma.begin_c, lemma.end_c]
    assert_equal m.dictionary_form_word_id, lemma.word_id
  end

  def test_normalized_form_morpheme_is_the_normalized_entry
    m = @tok.tokenize("附属").first

    assert_equal "付属", m.normalized_form_morpheme.surface
  end

  def test_a_word_that_is_its_own_form_returns_itself
    m = @tok.tokenize("東京").first

    assert_same m, m.dictionary_form_morpheme
    assert_same m, m.normalized_form_morpheme
  end

  def test_an_oov_word_is_its_own_form
    m = @tok.tokenize("ズィーガンボルト").find(&:oov?)

    assert_same m, m.dictionary_form_morpheme
  end

  # ── OOV morphemes ──

  def test_oov_morpheme_defaults_its_forms_to_the_surface
    pos_id = @tok.tokenize("カボス").first.part_of_speech_id
    m = @dict.oov_morpheme(pos_id, "ズィーガン", reading: "ジーガン")

    assert_predicate m, :oov?
    assert_equal %w[ズィーガン ジーガン ズィーガン ズィーガン],
                 [m.surface, m.reading_form, m.normalized_form, m.dictionary_form]
    assert_equal %w[名詞 普通名詞 一般], m.part_of_speech.first(3)
    assert_equal [-1, 0, 15, 0, 5], [m.dictionary_id, m.begin, m.end, m.begin_c, m.end_c]
    assert_equal ["ズィーガン"], m.split(mode: :a).map(&:surface)
  end

  def test_oov_morpheme_rejects_a_bad_pos_id
    assert_raises(ArgumentError) { @dict.oov_morpheme(65_000, "x") }
    assert_raises(ArgumentError) { @dict.oov_morpheme(1 << 20, "x") }
    assert_raises(ArgumentError) { @dict.oov_morpheme("名詞", "x") }
  end

  # ── Entries ──

  def test_entries_is_lazy_and_yields_standalone_morphemes
    enum = @dict.entries
    assert_kind_of Enumerator, enum

    first = enum.first(3)
    assert_equal 3, first.size
    first.each do |m|
      refute_predicate m, :oov?
      assert_equal [0, m.surface.bytesize], [m.begin, m.end]
    end

    seen = 0
    @dict.entries { break if (seen += 1) == 100 }
    assert_equal 100, seen
  end

  def test_lookup_all_entries_matches_exactly_after_normalizing
    found = @dict.lookup_all_entries("ｶﾎﾞｽ")

    assert_kind_of Kabosu::MorphemeList, found
    assert_equal ["カボス"], found.map(&:surface).uniq
  end

  # ── Normalizer ──

  def test_normalize_applies_the_dictionary_input_plugins
    assert_equal "カボス abc コンピューター", @dict.normalize("ｶﾎﾞｽ ＡＢＣ コンピュータ〜〜")
  end

  # ── User dictionaries, user_data, split_c ──

  def test_user_dictionary_round_trip
    with_user_dict do |dict|
      words = dict.create.tokenize("ズィーガンボルトとカボス協会").to_a
      zg = words.first
      kyokai = words.last

      assert_predicate zg, :user?
      assert_equal 1, zg.dictionary_id
      assert_equal "kabosu-fixture", zg.user_data
      assert_equal "協会", kyokai.user_data
      assert_equal 2, kyokai.c_unit_split.size
      assert_equal %w[カボス 協会], kyokai.split(mode: :a).map(&:surface)
      assert(dict.lookup("カボス協会").any? { _1.user? && _1.surface == "カボス協会" })
    end
  end

  def test_user_data_and_split_c_are_selectable_fields
    fields = @dict.create(fields: %i[user_data split_c]).fields

    assert_includes fields, "user_data"
    assert_includes fields, "split_c"
  end

  def test_a_user_dictionary_only_loads_with_its_own_system_dictionary
    others = Kabosu::DictManager.new.readable.map { _1[:path] } - [@system]
    skip "needs a second V1 system dictionary installed" if others.empty?

    with_user_dict do |_dict, user_dic|
      error = assert_raises(Kabosu::DictionaryError) do
        Kabosu::Dictionary.new(system_dict: others.first, user_dicts: [user_dic])
      end
      assert_match(/not compatible with the system dictionary/, error.message)
    end
  end

  def test_build_user_dict_reports_bad_csv
    Dir.mktmpdir do |dir|
      bad = File.join(dir, "bad.csv")
      File.write(bad, "not,a,lexicon\n")

      assert_raises(Kabosu::DictionaryError) do
        Kabosu.build_user_dict(bad, output: File.join(dir, "bad.dic"), system_dict: @system)
      end
    end
  end

  private

  def with_user_dict
    user_dic = self.class.user_dic_for(@system)
    yield Kabosu::Dictionary.new(system_dict: @system, user_dicts: [user_dic]), user_dic
  end
end
