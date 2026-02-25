require_relative "kabosu/version"
require_relative "kabosu/kabosu"
require_relative "kabosu/dict_manager"
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
      MorphemeList.new(_tokenize(text))
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
    @tokenizers ||= {}
    @tokenizers[[edition, mode]] ||= Dictionary.new(dict: dict_path(edition: edition)).create(mode)
    @tokenizers[[edition, mode]].tokenize(text)
  end
end
