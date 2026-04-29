require "rb_sys/extensiontask"
require "rake/testtask"

GEMSPEC = Gem::Specification.load("kabosu.gemspec")

# Platforms we precompile binary gems for. The source gem is still published
# as a fallback for anything not in this list (e.g. brand-new Ruby versions
# whose rake-compiler-dock images don't exist yet).
CROSS_PLATFORMS = %w[
  aarch64-linux
  aarch64-linux-musl
  arm64-darwin
  x86_64-darwin
  x86_64-linux
  x86_64-linux-musl
].freeze

RbSys::ExtensionTask.new("kabosu", GEMSPEC) do |ext|
  ext.lib_dir = "lib/kabosu"
  ext.source_pattern = "*.{rs,toml}"
  ext.cross_compile = true
  ext.cross_platform = CROSS_PLATFORMS
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

load File.expand_path("lib/kabosu/tasks.rake", __dir__)
load File.expand_path("lib/kabosu/release.rake", __dir__)

task default: %i[compile test]
