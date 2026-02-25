require_relative "test_helper"
require "kabosu/morpheme_list"

# Lightweight stand-in for Kabosu::Morpheme without needing the Rust extension
MockMorpheme = Struct.new(:surface, :reading_form, :dictionary_form,
                          :normalized_form, :part_of_speech, :oov?,
                          keyword_init: true)

class MorphemeListTest < Minitest::Test
  def setup
    @morphemes = [
      MockMorpheme.new(surface: "東京", reading_form: "トウキョウ",
                       dictionary_form: "東京", normalized_form: "東京",
                       part_of_speech: %w[名詞 固有名詞 地名 一般 * *], oov?: false),
      MockMorpheme.new(surface: "都", reading_form: "ト",
                       dictionary_form: "都", normalized_form: "都",
                       part_of_speech: %w[名詞 普通名詞 一般 * * *], oov?: false),
      MockMorpheme.new(surface: "に", reading_form: "ニ",
                       dictionary_form: "に", normalized_form: "に",
                       part_of_speech: %w[助詞 格助詞 * * * *], oov?: false),
    ]
    @list = Kabosu::MorphemeList.new(@morphemes)
  end

  # ── Enumerable ──

  def test_each_yields_morphemes
    yielded = []
    @list.each { yielded << _1 }
    assert_equal @morphemes, yielded
  end

  def test_is_enumerable
    assert_kind_of Enumerable, @list
  end

  def test_map
    assert_equal %w[東京 都 に], @list.map(&:surface)
  end

  def test_select
    nouns = @list.select { _1.part_of_speech.first == "名詞" }
    assert_equal 2, nouns.size
  end

  def test_any
    assert @list.any? { _1.surface == "東京" }
    refute @list.any? { _1.surface == "大阪" }
  end

  def test_none
    assert @list.none?(&:oov?)
  end

  # ── Accessors ──

  def test_size
    assert_equal 3, @list.size
  end

  def test_bracket_access
    assert_equal "東京", @list[0].surface
    assert_equal "都", @list[1].surface
  end

  def test_bracket_access_negative_index
    assert_equal "に", @list[-1].surface
  end

  # ── Convenience methods ──

  def test_surfaces
    assert_equal %w[東京 都 に], @list.surfaces
  end

  def test_readings
    assert_equal %w[トウキョウ ト ニ], @list.readings
  end

  def test_dictionary_forms
    assert_equal %w[東京 都 に], @list.dictionary_forms
  end

  # ── inspect ──

  def test_inspect_includes_size
    assert_match(/3 morphemes/, @list.inspect)
  end

  def test_inspect_includes_surfaces
    assert_match(/東京/, @list.inspect)
  end
end
