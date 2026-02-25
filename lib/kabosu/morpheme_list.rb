module Kabosu
  class MorphemeList
    include Enumerable

    def initialize(morphemes)
      @morphemes = morphemes
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

    def inspect
      "#<Kabosu::MorphemeList (#{size} morphemes): #{surfaces.join(" | ")}>"
    end
  end
end
