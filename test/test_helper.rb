require "minitest/autorun"
require "tmpdir"
require "fileutils"

# Lightweight stand-in for Kabosu::Morpheme that needs no native extension or
# dictionary. Shared by the MorphemeList and PosMatcher unit tests; callers pass
# only the keyword fields they care about (the rest default to nil).
MockMorpheme = Struct.new(
  :surface, :reading_form, :dictionary_form,
  :normalized_form, :part_of_speech, :oov?,
  keyword_init: true
)

# Skip an entire test class if no dictionary is installed
module RequiresDictionary
  module SkipHook
    def setup
      require "kabosu"
      skip "No dictionary installed. Run: rake kabosu:install" if Kabosu::Dictionary.list.empty?
      super
    end
  end

  def self.included(base)
    base.prepend(SkipHook)
  end
end
