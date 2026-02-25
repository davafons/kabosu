module Kabosu
  class MorphemeList
    include Enumerable

    attr_accessor :internal_cost

    def initialize(morphemes, internal_cost: nil)
      @morphemes = morphemes
      @internal_cost = internal_cost
    end

    def each(&block)
      @morphemes.each(&block)
    end

    def [](index)
      @morphemes[index]
    end

    def first(n = nil)
      n ? @morphemes.first(n) : @morphemes.first
    end

    def last(n = nil)
      n ? @morphemes.last(n) : @morphemes.last
    end

    def size
      @morphemes.size
    end

    def surfaces
      map(&:surface)
    end

    def readings
      map(&:reading_form)
    end

    def dictionary_forms
      map(&:dictionary_form)
    end

    def normalized_forms
      map(&:normalized_form)
    end

    def total_costs
      map(&:total_cost)
    end

    def synonym_group_ids
      map(&:synonym_group_ids)
    end

    # Joins all surfaces back into the original text (no spaces, for Japanese text).
    def to_text
      surfaces.join
    end

    # Filter morphemes by POS. Accepts a PosMatcher or an array pattern.
    # Returns a new MorphemeList with only matching morphemes.
    #
    #   list.select_pos(Kabosu::PosMatcher.nouns)
    #   list.select_pos(["名詞", "固有名詞"])
    #
    def select_pos(matcher_or_pattern)
      matcher = coerce_to_matcher(matcher_or_pattern)
      self.class.new(matcher.filter(@morphemes))
    end

    # Inverse of select_pos. Returns a new MorphemeList excluding matching morphemes.
    def reject_pos(matcher_or_pattern)
      matcher = coerce_to_matcher(matcher_or_pattern)
      self.class.new(matcher.reject(@morphemes))
    end

    def inspect
      base = "#<Kabosu::MorphemeList (#{size} morphemes)"
      base += " cost=#{@internal_cost}" if @internal_cost
      base + ": #{surfaces.join(" | ")}>"
    end

    private

    def coerce_to_matcher(matcher_or_pattern)
      case matcher_or_pattern
      when PosMatcher
        matcher_or_pattern
      when Array
        PosMatcher.new(matcher_or_pattern)
      else
        raise ArgumentError, "expected a PosMatcher or an Array pattern, got #{matcher_or_pattern.class}"
      end
    end
  end
end
