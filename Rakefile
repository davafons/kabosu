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

# Maintainer-only: re-copy the four Sudachi resource files (sudachi.json,
# char.def, unk.def, rewrite.def) from the cargo-resolved sudachi crate
# into lib/kabosu/resources/. Run this every time you bump the sudachi
# dependency in ext/kabosu/Cargo.toml. The bundled files are
# version-locked to sudachi.rs and shipped to consumers because the
# crate's own default config path is captured at build time and isn't
# usable from a precompiled gem.
namespace :sudachi do
  RESOURCE_FILES = %w[sudachi.json char.def unk.def rewrite.def].freeze
  BUNDLED_DIR = "lib/kabosu/resources".freeze

  desc "Sync bundled Sudachi resources from the resolved cargo dep"
  task :sync_resources do
    require "json"
    require "fileutils"

    metadata = JSON.parse(`cargo metadata --format-version=1 --manifest-path ext/kabosu/Cargo.toml`)
    sudachi = metadata.fetch("packages").find { |p| p["name"] == "sudachi" }
    abort "sudachi crate not found — run `cargo fetch` first" unless sudachi

    src = File.expand_path("../resources", File.dirname(sudachi.fetch("manifest_path")))
    abort "sudachi resources dir #{src} not found" unless Dir.exist?(src)

    FileUtils.mkdir_p(BUNDLED_DIR)
    RESOURCE_FILES.each do |file|
      from = File.join(src, file)
      to = File.join(BUNDLED_DIR, file)
      FileUtils.cp(from, to)
      puts "synced #{file}"
    end
    puts "Done. Review the diff before committing."
  end

  desc "Fail if bundled Sudachi resources have drifted from the cargo dep"
  task :check_resources do
    Rake::Task["sudachi:sync_resources"].invoke
    out = `git status --porcelain #{BUNDLED_DIR}`
    if out.empty?
      puts "Bundled resources match sudachi.rs — clean."
    else
      puts "Bundled resources are stale relative to sudachi.rs:"
      puts out
      abort "Run `rake sudachi:sync_resources` and commit the diff."
    end
  end
end

# Conformance/parity fixture regeneration. The *_test.rb suites run in `rake
# test` against committed JSONL fixtures and skip gracefully if a fixture is
# missing or the installed dictionary has drifted. These tasks rebuild those
# fixtures — run them after bumping the sudachi.rs tag or the dictionary.
namespace :conformance do
  desc "Regenerate raw-sudachi.rs conformance fixtures (needs a Rust toolchain)"
  task :generate do
    ruby "-Ilib", "test/conformance/generate.rb"
  end
end

namespace :parity do
  desc "Create the SudachiPy virtualenv used by the parity suite"
  task :setup do
    sh "test/parity/setup.sh"
  end

  desc "Regenerate SudachiPy parity fixtures (needs the parity:setup venv)"
  task :generate do
    ruby "-Ilib", "test/parity/generate.rb"
  end
end

task default: %i[compile test]
