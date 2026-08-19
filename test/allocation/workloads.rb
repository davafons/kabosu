# frozen_string_literal: true

# A workload is a name, a body, and the unit of work it does.
#
# Bodies must be allocation-DETERMINISTIC: no Time, no rand, no object_id, no I/O,
# no interpolation of a varying counter. The magic comment above is not optional
# either — a bare string literal inside a loop is one allocation per iteration and
# would drown the signal.
module Allocation
  module Workloads
    # Committed on purpose. bench/fixtures/*.txt is gitignored (bench/setup
    # downloads it), so CI would have nothing to measure; and
    # test/conformance/corpus.txt has its SHA pinned in that suite's meta.json, so
    # editing it there would silently skip conformance. Changing a line here
    # changes every recorded number.
    CORPUS = File.readlines(File.expand_path("corpus.txt", __dir__), chomp: true)
                 .reject { |line| line.empty? || line.start_with?("#") }.freeze

    module_function

    def tokenizers(dict)
      { c: dict.create(mode: :c), b: dict.create(mode: :b) }
    end

    # Floor: tokenize and touch nothing. Everything else reads against this.
    def tokenize_only(toks)
      CORPUS.each { |line| toks[:c].tokenize(line) }
    end

    # THE ONE THAT MATTERS. Modelled on the consuming app's own hot path: mode C
    # and mode B over the same text, then several passes over the SAME morphemes
    # asking the same questions. This call shape is what produced 16.5 surface
    # calls and 35.7 part_of_speech calls per morpheme — the ratio that no
    # allocation profiler reports, because every one of those calls looks like
    # ordinary hot-path work rather than the duplicate it is.
    def realistic(toks)
      CORPUS.each do |line|
        ms = toks[:c].tokenize(line).to_a
        toks[:b].tokenize(line).to_a
        3.times do
          ms.each do |m|
            m.surface
            m.part_of_speech.first
            m.dictionary_form
          end
        end
      end
    end

    # The `+str` idiom the consumer uses to build a group's surface. It is safe
    # ONLY because the cached surface is frozen: on a mutable shared String `+s`
    # returns self, and the `<<` would write straight through into the cache.
    def group_surfaces(toks)
      CORPUS.each do |line|
        ms = toks[:c].tokenize(line).to_a
        buffer = +ms.first.surface
        ms.drop(1).each { |m| buffer << m.surface }
      end
    end

    def units = CORPUS.size

    def all = { "tokenize_only" => method(:tokenize_only),
                "realistic" => method(:realistic),
                "group_surfaces" => method(:group_surfaces) }
  end
end
