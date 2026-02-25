module Kabosu
  class MorphemeList
    include Enumerable

    attr_accessor :internal_cost

    def initialize(source_or_morphemes, internal_cost: nil)
      @source = source_or_morphemes if lazy_source?(source_or_morphemes)
      @morphemes = @source ? Array.new(@source.size) : source_or_morphemes
      @internal_cost = internal_cost || (@source&.internal_cost)
    end

    def each(&block)
      return enum_for(:each) unless block

      if @source
        i = 0
        while i < size
          block.call(fetch(i))
          i += 1
        end
      else
        @morphemes.each(&block)
      end
    end

    def [](index)
      return to_a[index] if index.is_a?(Range)

      idx = normalize_index(index)
      return nil if idx.nil?

      fetch(idx)
    end

    def first(n = nil)
      return self[0] unless n

      n = Integer(n)
      raise ArgumentError, "negative array size" if n.negative?

      limit = [n, size].min
      (0...limit).map { fetch(_1) }
    end

    def last(n = nil)
      return self[-1] unless n

      n = Integer(n)
      raise ArgumentError, "negative array size" if n.negative?

      start = [size - n, 0].max
      (start...size).map { fetch(_1) }
    end

    def size
      @morphemes.size
    end

    def empty?
      @morphemes.empty?
    end

    def surfaces
      return @source.surfaces if @source&.respond_to?(:surfaces)

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
      self.class.new(matcher.filter(to_a))
    end

    # Inverse of select_pos. Returns a new MorphemeList excluding matching morphemes.
    def reject_pos(matcher_or_pattern)
      matcher = coerce_to_matcher(matcher_or_pattern)
      self.class.new(matcher.reject(to_a))
    end

    def to_a
      return @morphemes.dup unless @source

      (0...size).map { fetch(_1) }
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

    def lazy_source?(obj)
      obj.respond_to?(:morpheme_at) && obj.respond_to?(:size) && obj.respond_to?(:surfaces)
    end

    def normalize_index(index)
      return nil if size.zero?

      idx = Integer(index)
      idx += size if idx.negative?
      return nil if idx.negative? || idx >= size

      idx
    end

    def fetch(idx)
      return @morphemes[idx] unless @source

      @morphemes[idx] ||= @source.morpheme_at(idx)
    end
  end
end
