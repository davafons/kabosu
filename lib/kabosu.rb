require_relative "kabosu/version"
require_relative "kabosu/kabosu"
require_relative "kabosu/dict_manager"
require_relative "kabosu/pos_matcher"
require_relative "kabosu/morpheme_list"

module Kabosu
  # ── Dictionary.new: keyword API + auto-discovery ──

  class Dictionary
    class << self
      alias_method :_new, :new

      def new(config: nil, dict: nil)
        dict ||= Kabosu.dict_path
        _new(config, dict)
      end
    end
  end

  # ── Tokenizer: wrap output in MorphemeList ──

  class Tokenizer
    alias_method :_tokenize, :tokenize

    def tokenize(text)
      morphemes = _tokenize(text)
      cost = respond_to?(:internal_cost) ? internal_cost : nil
      MorphemeList.new(morphemes, internal_cost: cost)
    end

    if method_defined?(:tokenize_sentences) || instance_methods(false).include?(:tokenize_sentences)
      alias_method :_tokenize_sentences, :tokenize_sentences

      def tokenize_sentences(text)
        _tokenize_sentences(text).map { |morphemes| MorphemeList.new(morphemes) }
      end
    end
  end

  # ── StatefulTokenizer: wrap output in MorphemeList ──

  class StatefulTokenizer
    alias_method :_tokenize, :tokenize

    def tokenize(text)
      morphemes = _tokenize(text)
      cost = respond_to?(:internal_cost) ? internal_cost : nil
      MorphemeList.new(morphemes, internal_cost: cost)
    end

    if method_defined?(:tokenize_sentences) || instance_methods(false).include?(:tokenize_sentences)
      alias_method :_tokenize_sentences, :tokenize_sentences

      def tokenize_sentences(text)
        _tokenize_sentences(text).map { |morphemes| MorphemeList.new(morphemes) }
      end
    end
  end

  # ── Dictionary management ──

  def self.dict_manager
    @dict_manager ||= DictManager.new
  end

  def self.install_dictionary(edition = "core", version: nil)
    dict_manager.install(edition, version: version)
  end

  def self.dict_path(edition: nil)
    dict_manager.find(edition: edition)
  end

  def self.dictionaries
    dict_manager.installed
  end

  # ── Convenience tokenization ──

  # Tokenize text using the best available dictionary.
  #
  #   Kabosu.tokenize("東京都に住んでいる")
  #   Kabosu.tokenize("東京都に住んでいる", mode: "A")
  #   Kabosu.tokenize("東京都に住んでいる", edition: "small")
  #
  def self.tokenize(text, mode: "C", edition: nil)
    tokenizer = cached_tokenizer(edition: edition, mode: mode)
    tokenizer.tokenize(text)
  end

  # Tokenize text into sentences. Returns an array of MorphemeList objects,
  # one per sentence.
  #
  #   Kabosu.tokenize_sentences("東京都に住んでいる。大阪も好きだ。")
  #
  def self.tokenize_sentences(text, mode: "C", edition: nil)
    tokenizer = cached_tokenizer(edition: edition, mode: mode)
    if tokenizer.respond_to?(:_tokenize_sentences)
      tokenizer.tokenize_sentences(text)
    elsif tokenizer.respond_to?(:tokenize_sentences)
      # Fallback if the alias wasn't set up (Rust method not yet available)
      tokenizer.tokenize_sentences(text).map { |morphemes| MorphemeList.new(morphemes) }
    else
      # Final fallback: treat entire text as a single sentence
      [tokenizer.tokenize(text)]
    end
  end

  # Convenience factory for PosMatcher.
  #
  #   nouns = Kabosu.pos_matcher("名詞")
  #   verbs = Kabosu.pos_matcher(["動詞", "*", "*", "*"])
  #   custom = Kabosu.pos_matcher { |pos| pos[0] == "動詞" }
  #
  def self.pos_matcher(*patterns, &block)
    if block
      PosMatcher.new(&block)
    elsif patterns.length == 1 && patterns[0].is_a?(String)
      # Shorthand: single string is treated as first POS element
      PosMatcher.new([patterns[0]])
    else
      PosMatcher.new(*patterns)
    end
  end

  # Create a StatefulTokenizer for efficient batch processing.
  # Reuses internal buffers across calls.
  #
  #   tok = Kabosu.batch_tokenizer(mode: "A")
  #   texts.each { |t| results << tok.tokenize(t) }
  #
  def self.batch_tokenizer(mode: "C", edition: nil)
    Dictionary.new(dict: dict_path(edition: edition)).create_stateful(mode)
  end

  # @api private
  def self.cached_tokenizer(edition:, mode:)
    @tokenizers ||= {}
    @tokenizers[[edition, mode]] ||= Dictionary.new(dict: dict_path(edition: edition)).create(mode)
  end
  private_class_method :cached_tokenizer
end
