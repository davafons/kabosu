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

    # jpdb-style grouping performed natively in Rust when backed by a lazy
    # source. Falls back to a Ruby implementation for already-materialized
    # lists so the method is always safe to call.
    def group_morphemes
      if @source&.respond_to?(:group_morphemes)
        return @source.group_morphemes
      end

      groups = []
      each do |m|
        last = groups.last
        if last && content_word?(last.first) && extends_group?(m, last.last)
          last << m
        else
          groups << [m]
        end
      end
      groups
    end

    private

    def content_word?(morpheme)
      !%w[助詞 助動詞 補助記号 記号 空白].include?(morpheme.part_of_speech.first)
    end

    def extends_group?(morpheme, prev = nil)
      pos = morpheme.part_of_speech
      pos1 = pos[0]
      pos1 == "助動詞" ||
        (pos1 == "助詞" && !clause_boundary?(morpheme) &&
         (pos[1] == "接続助詞" ||
          (pos[1] == "副助詞" && prev && %w[動詞 形容詞 形状詞].include?(prev.part_of_speech[0])))) ||
        (pos1 == "動詞" && pos[1] == "非自立可能" &&
         prev && prev.part_of_speech[0] == "助詞" && %w[て で].include?(prev.surface))
    end

    def clause_boundary?(morpheme)
      return false unless morpheme
      pos = morpheme.part_of_speech
      return true if pos[0] == "助詞" &&
                     %w[ながら たら ば と のに から ので けれど けど つつ なり や か かどうか とも].include?(morpheme.surface)
      return true if pos[0] == "助詞" && pos[1] == "接続助詞" && morpheme.surface == "が"
      false
    end

    public

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
