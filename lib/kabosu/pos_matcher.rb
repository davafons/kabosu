module Kabosu
  class PosMatcher
    # Build a matcher from POS patterns or a block.
    #
    #   # From a block
    #   PosMatcher.new { |pos| pos[0] == "名詞" }
    #
    #   # Single pattern (array of strings; "*" or nil = match anything)
    #   PosMatcher.new(["名詞", "固有名詞", "*", "*"])
    #
    #   # Multiple patterns (matches if any pattern matches)
    #   PosMatcher.new(["名詞", "固有名詞"], ["動詞", "*", "*", "*"])
    #
    def initialize(*patterns, &block)
      if block
        raise ArgumentError, "cannot supply both patterns and a block" unless patterns.empty?

        @proc = block
      elsif patterns.empty?
        raise ArgumentError, "must supply at least one pattern or a block"
      else
        @patterns = patterns.map(&:freeze).freeze
      end

      freeze
    end

    # Returns true if the morpheme (or raw POS array) matches this matcher.
    def match?(morpheme_or_pos)
      pos = extract_pos(morpheme_or_pos)

      if @proc
        @proc.call(pos)
      else
        @patterns.any? { |pattern| pattern_match?(pattern, pos) }
      end
    end

    # Return matching morphemes as an Array.
    def filter(morphemes)
      morphemes.select { |m| match?(m) }
    end

    # Return non-matching morphemes as an Array.
    def reject(morphemes)
      morphemes.reject { |m| match?(m) }
    end

    # Union: matches if either matcher matches.
    def |(other)
      a = self
      b = other
      PosMatcher.new { |pos| a.match?(pos) || b.match?(pos) }
    end

    # Intersection: matches if both matchers match.
    def &(other)
      a = self
      b = other
      PosMatcher.new { |pos| a.match?(pos) && b.match?(pos) }
    end

    # Difference: matches self but not other.
    def -(other)
      difference(other)
    end

    def difference(other)
      a = self
      b = other
      PosMatcher.new { |pos| a.match?(pos) && !b.match?(pos) }
    end

    # ── Pre-built matchers ──

    def self.nouns
      @nouns ||= new(["名詞"])
    end

    def self.verbs
      @verbs ||= new(["動詞"])
    end

    def self.adjectives
      @adjectives ||= new(["形容詞"])
    end

    def self.particles
      @particles ||= new(["助詞"])
    end

    def self.auxiliary_verbs
      @auxiliary_verbs ||= new(["助動詞"])
    end

    def self.adverbs
      @adverbs ||= new(["副詞"])
    end

    def self.proper_nouns
      @proper_nouns ||= new(%w[名詞 固有名詞])
    end

    private

    def extract_pos(morpheme_or_pos)
      if morpheme_or_pos.is_a?(Array)
        morpheme_or_pos
      elsif morpheme_or_pos.respond_to?(:part_of_speech)
        morpheme_or_pos.part_of_speech
      else
        raise ArgumentError, "expected an Array or an object responding to #part_of_speech"
      end
    end

    def pattern_match?(pattern, pos)
      pattern.each_with_index.all? do |slot, i|
        slot.nil? || slot == "*" || slot == pos[i]
      end
    end
  end
end
