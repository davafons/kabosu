require_relative "kabosu/version"

# Load the native extension. Precompiled gems place it under a per-Ruby-version
# subdirectory (lib/kabosu/3.3/kabosu.bundle, etc.); a source build leaves it
# at lib/kabosu/kabosu.{bundle,so}. Try the version-suffixed path first, fall
# back to the flat path so dev/source builds keep working.
begin
  major_minor = RUBY_VERSION.split(".").take(2).join(".")
  require_relative "kabosu/#{major_minor}/kabosu"
rescue LoadError
  require_relative "kabosu/kabosu"
end

require_relative "kabosu/dict_manager"
require_relative "kabosu/pos_matcher"
require_relative "kabosu/morpheme_list"
require_relative "kabosu/railtie" if defined?(Rails::Railtie)

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
    DEFAULT_CONFIG_PATH = File.expand_path("kabosu/resources/sudachi.json", __dir__).freeze

    class << self
      alias _new new

      def new(config: nil, system_dict: nil, user_dicts: nil)
        raise ArgumentError, "config must be a String or nil" unless config.nil? || config.is_a?(String)
        raise ArgumentError, "system_dict must be a String or nil" unless system_dict.nil? || system_dict.is_a?(String)
        unless user_dicts.nil? || user_dicts.is_a?(Array)
          raise ArgumentError, "user_dicts must be an Array<String> or nil"
        end
        raise ArgumentError, "user_dicts must contain only String values" if user_dicts&.any? { !_1.is_a?(String) }

        raise ArgumentError, "either config or system_dict is required" if config.nil? && system_dict.nil?

        # Default to the sudachi.json bundled with this gem when only
        # system_dict is given. sudachi.rs's own default config path is
        # captured via env!("CARGO_MANIFEST_DIR") and doesn't exist on
        # consumers' machines once the gem is precompiled and shipped.
        config ||= DEFAULT_CONFIG_PATH

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
        if message.include?("V0 version")
          return DictionaryError.new(
            "#{message}: a system or user dictionary is in the pre-V1 format, which sudachi.rs 0.7+ cannot read. " \
            "Install SudachiDict #{DictManager::MIN_VERSION} or later (rake kabosu:install) " \
            "and rebuild user dictionaries against it."
          )
        end

        if (config && system_dict.nil?) || message.match?(/config|setting\.json|json/i)
          ConfigError.new(message)
        else
          DictionaryError.new(message)
        end
      end

      def dict_manager
        @dict_manager ||= DictManager.new
      end
    end

    alias _create create
    alias _lookup lookup

    def create(**options)
      unknown = options.keys - %i[mode fields debug projection]
      raise ArgumentError, "unknown keyword(s): #{unknown.join(", ")}" unless unknown.empty?

      mode = options.fetch(:mode, MODE_C)
      fields = options.fetch(:fields, nil)
      debug = options.fetch(:debug, false)
      projection = options.fetch(:projection, nil)

      raise ArgumentError, "fields must be an Array<String|Symbol> or nil" unless fields.nil? || fields.is_a?(Array)
      if fields&.any? { !(_1.is_a?(String) || _1.is_a?(Symbol)) }
        raise ArgumentError, "fields must contain only String or Symbol values"
      end
      raise ArgumentError, "debug must be true or false" unless [true, false].include?(debug)

      raise NotImplementedError, "projection is not supported yet" unless projection.nil?

      mode_str = Kabosu.__send__(:normalize_mode, mode)
      _create(mode_str, fields, debug)
    end

    def lookup(text)
      raise ArgumentError, "text must be a String" unless text.is_a?(String)

      MorphemeList.new(_lookup(text))
    rescue RuntimeError => e
      raise LookupError.new(e.message), cause: e
    end

    # Every public dictionary entry as a standalone Morpheme (offsets cover its
    # own headword). Lazy: a `full` dictionary holds millions of entries, so
    # chain with `.lazy`, `.first(n)` or `.each` rather than `.to_a`.
    #
    #   dict.entries.lazy.select { _1.user? }.first(10)
    def entries(&block)
      return enum_for(:entries) unless block

      _each_entry(&block)
      self
    end

    # Like #lookup, but exact matches only and found by scanning every entry,
    # so it also finds entries that are not indexed for lookup. Slow.
    def lookup_all_entries(surface)
      raise ArgumentError, "surface must be a String" unless surface.is_a?(String)

      MorphemeList.new(_lookup_all_entries(surface))
    rescue RuntimeError => e
      raise LookupError.new(e.message), cause: e
    end

    # Builds an out-of-vocabulary Morpheme by hand. The forms default to the
    # surface. pos_id comes from Morpheme#part_of_speech_id.
    #
    #   dict.oov_morpheme(pos_id, "ズィーガンボルト", reading: "ズィーガンボルト")
    def oov_morpheme(pos_id, surface, reading: nil, normalized_form: nil, dictionary_form: nil)
      raise ArgumentError, "pos_id must be an Integer" unless pos_id.is_a?(Integer)
      raise ArgumentError, "surface must be a String" unless surface.is_a?(String)

      _oov_morpheme(pos_id, surface, reading, normalized_form, dictionary_form)
    rescue RangeError, RuntimeError => e
      raise ArgumentError, "invalid part-of-speech id #{pos_id}: #{e.message}"
    end
  end

  # ── Tokenizer: wrap output in MorphemeList ──

  class Tokenizer
    alias _tokenize tokenize

    def tokenize(text)
      raise ArgumentError, "text must be a String" unless text.is_a?(String)

      batch = _tokenize(text)
      cost = batch.respond_to?(:internal_cost) ? batch.internal_cost : nil
      MorphemeList.new(batch, internal_cost: cost)
    rescue RuntimeError => e
      raise TokenizationError.new(e.message), cause: e
    end
  end

  class Morpheme
    alias _split split

    def split(mode: MODE_C, add_single: true)
      raise ArgumentError, "add_single must be true or false" unless [true, false].include?(add_single)

      mode_str = Kabosu.__send__(:normalize_mode, mode)
      MorphemeList.new(_split(mode_str, nil, add_single))
    rescue RuntimeError => e
      raise TokenizationError.new(e.message), cause: e
    end
  end

  # Compiles user-dictionary CSV(s) into a binary user dictionary. The result
  # loads only next to the system dictionary it was built against, so rebuild
  # whenever that changes (including the move to sudachi.rs 0.7).
  #
  #   Kabosu.build_user_dict("names.csv", output: "names.dic")
  #   Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path, user_dicts: ["names.dic"])
  def self.build_user_dict(inputs, output:, system_dict: Dictionary.path, description: nil)
    inputs = Array(inputs)
    raise ArgumentError, "inputs must be String paths" unless inputs.all?(String)
    raise ArgumentError, "output must be a String" unless output.is_a?(String)

    _build_user_dict(inputs, system_dict, output, description)
    output
  rescue RuntimeError => e
    raise DictionaryError.new(e.message), cause: e
  end

  def self.split_sentences(text, limit: nil, with_checker: false, ranges: false, dictionary: nil)
    raise ArgumentError, "text must be a String" unless text.is_a?(String)
    raise ArgumentError, "limit must be an Integer or nil" unless limit.nil? || limit.is_a?(Integer)
    raise ArgumentError, "limit must be greater than 0" if limit && limit < 1
    raise ArgumentError, "with_checker must be true or false" unless [true, false].include?(with_checker)
    raise ArgumentError, "ranges must be true or false" unless [true, false].include?(ranges)
    raise ArgumentError, "dictionary must be a String path or nil" unless dictionary.nil? || dictionary.is_a?(String)

    dict_path = nil
    dict_path = dictionary || Dictionary.path if with_checker

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
    raise ArgumentError, "text must be a String" unless text.is_a?(String)
    raise ArgumentError, "tokenizer must be a Kabosu::Tokenizer" unless tokenizer.is_a?(Tokenizer)

    batch = tokenizer.__send__(:_tokenize, text)
    cost = batch.respond_to?(:internal_cost) ? batch.internal_cost : nil
    MorphemeList.new(batch, internal_cost: cost)
  rescue RuntimeError => e
    raise TokenizationError.new(e.message), cause: e
  end
end
