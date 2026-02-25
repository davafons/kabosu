require "minitest/autorun"
require "tmpdir"
require "fileutils"

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
