require_relative "kabosu/version"
require_relative "kabosu/kabosu"
require_relative "kabosu/dict_manager"
require_relative "kabosu/pos_matcher"
require_relative "kabosu/morpheme_list"

module Kabosu
  class Error < StandardError; end
  class ConfigError < Error; end
  class DictionaryError < Error; end
  class LookupError < Error; end
  class TokenizationError < Error; end
  class SentenceSplitError < Error; end

  class SentenceRange
    attr_reader :start, :end, :text

    def initialize(start, finish, text)
      @start = start
      @end = finish
      @text = text
    end

    def to_a
      [@start, @end, @text]
    end
  end

  remove_const(:MODE_A) if const_defined?(:MODE_A, false)
  remove_const(:MODE_B) if const_defined?(:MODE_B, false)
  remove_const(:MODE_C) if const_defined?(:MODE_C, false)
  MODE_A = :a
  MODE_B = :b
  MODE_C = :c
  private_constant :TokenBatch if const_defined?(:TokenBatch, false)

  def self.normalize_mode(mode, param_name: "mode")
    case mode
    when :a
      "A"
    when :b
      "B"
    when :c
      "C"
    else
      raise ArgumentError, "invalid #{param_name} #{mode.inspect}; expected :a, :b, or :c"
    end
  end
  private_class_method :normalize_mode

  # ── Dictionary: keyword API and management ──

  class Dictionary
    class << self
      alias_method :_new, :new

      def new(config: nil, system_dict: nil, user_dicts: nil)
        unless config.nil? || config.is_a?(String)
          raise ArgumentError, "config must be a String or nil"
        end
        unless system_dict.nil? || system_dict.is_a?(String)
          raise ArgumentError, "system_dict must be a String or nil"
        end
        unless user_dicts.nil? || user_dicts.is_a?(Array)
          raise ArgumentError, "user_dicts must be an Array<String> or nil"
        end
        if user_dicts&.any? { !_1.is_a?(String) }
          raise ArgumentError, "user_dicts must contain only String values"
        end

        if config.nil? && system_dict.nil?
          raise ArgumentError, "either config or system_dict is required"
        end
        _new(config, system_dict, user_dicts)
      rescue RuntimeError => e
        raise map_dictionary_init_error(e, config: config, system_dict: system_dict)
      end

      def install(edition = "core", version: nil)
        dict_manager.install(edition, version: version)
      end

      def path(edition: nil)
        dict_manager.find(edition: edition)
      end

      def list
        dict_manager.installed
      end

      private

      def map_dictionary_init_error(error, config:, system_dict:)
        message = error.message
        if config && system_dict.nil?
          ConfigError.new(message)
        elsif message.match?(/config|setting\.json|json/i)
          ConfigError.new(message)
        else
          DictionaryError.new(message)
        end
      end

      def dict_manager
        @dict_manager ||= DictManager.new
      end
    end

    alias_method :_create, :create
    alias_method :_lookup, :lookup

    def create(**options)
      unknown = options.keys - %i[mode fields debug projection]
      raise ArgumentError, "unknown keyword(s): #{unknown.join(', ')}" unless unknown.empty?

      mode = options.fetch(:mode, MODE_C)
      fields = options.fetch(:fields, nil)
      debug = options.fetch(:debug, false)
      projection = options.fetch(:projection, nil)

      unless fields.nil? || fields.is_a?(Array)
        raise ArgumentError, "fields must be an Array<String|Symbol> or nil"
      end
      if fields&.any? { !(_1.is_a?(String) || _1.is_a?(Symbol)) }
        raise ArgumentError, "fields must contain only String or Symbol values"
      end
      unless debug == true || debug == false
        raise ArgumentError, "debug must be true or false"
      end

      unless projection.nil?
        raise NotImplementedError, "projection is not supported yet"
      end

      mode_str = Kabosu.__send__(:normalize_mode, mode)
      _create(mode_str, fields, debug)
    end

    def lookup(text)
      unless text.is_a?(String)
        raise ArgumentError, "text must be a String"
      end
      MorphemeList.new(_lookup(text))
    rescue RuntimeError => e
      raise LookupError.new(e.message), cause: e
    end
  end

  # ── Tokenizer: wrap output in MorphemeList ──

  class Tokenizer
    alias_method :_tokenize, :tokenize

    def tokenize(text)
      unless text.is_a?(String)
        raise ArgumentError, "text must be a String"
      end

      batch = _tokenize(text)
      cost = batch.respond_to?(:internal_cost) ? batch.internal_cost : nil
      MorphemeList.new(batch, internal_cost: cost)
    rescue RuntimeError => e
      raise TokenizationError.new(e.message), cause: e
    end

    alias_method :_tokenize_surfaces, :tokenize_surfaces
    alias_method :_tokenize_readings, :tokenize_readings
    alias_method :_tokenize_dictionary_forms, :tokenize_dictionary_forms
    alias_method :_tokenize_normalized_forms, :tokenize_normalized_forms

    def tokenize_surfaces(text)
      unless text.is_a?(String)
        raise ArgumentError, "text must be a String"
      end
      _tokenize_surfaces(text)
    rescue RuntimeError => e
      raise TokenizationError.new(e.message), cause: e
    end

    def tokenize_readings(text)
      unless text.is_a?(String)
        raise ArgumentError, "text must be a String"
      end
      _tokenize_readings(text)
    rescue RuntimeError => e
      raise TokenizationError.new(e.message), cause: e
    end

    def tokenize_dictionary_forms(text)
      unless text.is_a?(String)
        raise ArgumentError, "text must be a String"
      end
      _tokenize_dictionary_forms(text)
    rescue RuntimeError => e
      raise TokenizationError.new(e.message), cause: e
    end

    def tokenize_normalized_forms(text)
      unless text.is_a?(String)
        raise ArgumentError, "text must be a String"
      end
      _tokenize_normalized_forms(text)
    rescue RuntimeError => e
      raise TokenizationError.new(e.message), cause: e
    end
  end

  class Morpheme
    alias_method :_split, :split

    def split(mode: MODE_C, add_single: true)
      unless add_single == true || add_single == false
        raise ArgumentError, "add_single must be true or false"
      end
      mode_str = Kabosu.__send__(:normalize_mode, mode)
      MorphemeList.new(_split(mode_str, nil, add_single))
    rescue RuntimeError => e
      raise TokenizationError.new(e.message), cause: e
    end
  end

  def self.split_sentences(text, limit: nil, with_checker: false, ranges: false, dictionary: nil)
    unless text.is_a?(String)
      raise ArgumentError, "text must be a String"
    end
    unless limit.nil? || limit.is_a?(Integer)
      raise ArgumentError, "limit must be an Integer or nil"
    end
    if limit && limit < 1
      raise ArgumentError, "limit must be greater than 0"
    end
    unless with_checker == true || with_checker == false
      raise ArgumentError, "with_checker must be true or false"
    end
    unless ranges == true || ranges == false
      raise ArgumentError, "ranges must be true or false"
    end
    unless dictionary.nil? || dictionary.is_a?(String)
      raise ArgumentError, "dictionary must be a String path or nil"
    end

    dict_path = nil
    if with_checker
      dict_path = dictionary || Dictionary.path
    end

    if ranges
      _split_sentences_with_ranges(text, limit, dict_path).map do |(start, finish, sentence)|
        SentenceRange.new(start, finish, sentence)
      end
    else
      _split_sentences(text, limit, dict_path)
    end
  rescue RuntimeError => e
    raise SentenceSplitError.new(e.message), cause: e
  end

  # ── Convenience tokenization ──

  # Tokenize text using an explicitly provided tokenizer.
  #
  #   dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
  #   tok = dict.create(mode: :a)
  #   Kabosu.tokenize("東京都に住んでいる", tokenizer: tok)
  #
  def self.tokenize(text, tokenizer:)
    unless text.is_a?(String)
      raise ArgumentError, "text must be a String"
    end
    unless tokenizer.is_a?(Tokenizer)
      raise ArgumentError, "tokenizer must be a Kabosu::Tokenizer"
    end

    batch = tokenizer.__send__(:_tokenize, text)
    cost = batch.respond_to?(:internal_cost) ? batch.internal_cost : nil
    MorphemeList.new(batch, internal_cost: cost)
  rescue RuntimeError => e
    raise TokenizationError.new(e.message), cause: e
  end
end
