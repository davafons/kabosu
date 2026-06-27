# Regenerates the conformance reference fixtures by running the raw sudachi.rs
# reference dumper (test/conformance/reference) over the shared corpus in all
# three split modes, plus a meta.json describing what produced them.
#
#   ruby -Ilib test/conformance/generate.rb        # uses the `core` edition
#   KABOSU_DICT_EDITION=full ruby -Ilib test/conformance/generate.rb
#
# Commit the regenerated fixtures so `rake test` can run the comparison without
# a Rust toolchain. Re-run this whenever the sudachi.rs tag or the installed
# dictionary changes.

require "json"
require "fileutils"
require "kabosu"
require_relative "corpus_helper"

DIR = __dir__
REFERENCE_DIR = File.join(DIR, "reference")
FIXTURES_DIR = File.join(DIR, "fixtures")
MODES = %w[A B C].freeze
EDITION = ENV.fetch("KABOSU_DICT_EDITION", "core")

# The sudachi.rs tag the reference links — keep in sync with the crate manifest.
SUDACHI_TAG = File.read(File.join(REFERENCE_DIR, "Cargo.toml"))[/tag = "(v[0-9.]+)"/, 1]

def dict_entry(edition)
  entry = Kabosu::Dictionary.list.find { _1[:edition] == edition }
  abort "No '#{edition}' dictionary installed. Run: rake kabosu:install[#{edition}]" unless entry
  entry
end

def build_reference
  puts "Building reference dumper (cargo build --release)…"
  ok = system("cargo", "build", "--release", "--manifest-path", File.join(REFERENCE_DIR, "Cargo.toml"))
  abort "cargo build failed" unless ok
end

def run_reference(bin, dict_path, mode)
  out = IO.popen([bin, ConformanceCorpus::PATH, dict_path, mode], &:read)
  abort "reference_dump exited non-zero for mode #{mode}" unless $?.success?
  out
end

entry = dict_entry(EDITION)
dict_path = entry[:path]
bin = File.join(REFERENCE_DIR, "target", "release", "reference_dump")

build_reference unless File.executable?(bin)
build_reference # always rebuild: cheap once compiled, guarantees the tag matches

FileUtils.mkdir_p(FIXTURES_DIR)

MODES.each do |mode|
  output = run_reference(bin, dict_path, mode)
  path = File.join(FIXTURES_DIR, "reference_#{mode}.jsonl")
  File.write(path, output)
  puts "wrote #{File.basename(path)} (#{output.count("\n")} morphemes)"
end

meta = {
  "sudachi_tag" => SUDACHI_TAG,
  "dict_edition" => EDITION,
  "dict_version" => entry[:version],
  "corpus_sha256" => ConformanceCorpus.sha256,
  "modes" => MODES
}
File.write(File.join(FIXTURES_DIR, "meta.json"), "#{JSON.pretty_generate(meta)}\n")
puts "wrote meta.json: #{meta.slice("sudachi_tag", "dict_edition", "dict_version")}"
