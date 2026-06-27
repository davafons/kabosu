# Regenerates the SudachiPy parity fixtures by running the official Python
# bindings (test/parity/dump_sudachipy.py) over the shared corpus in all three
# split modes, pointed at the same dictionary, config, and resources kabosu
# uses. Requires the venv created by test/parity/setup.sh.
#
#   ruby -Ilib test/parity/generate.rb
#
# Commit the regenerated fixtures so `rake test` can run the comparison without
# a Python toolchain.

require "json"
require "fileutils"
require "kabosu"
require_relative "../conformance/corpus_helper"

DIR = __dir__
VENV_PYTHON = File.join(DIR, "venv", "bin", "python")
DUMP_SCRIPT = File.join(DIR, "dump_sudachipy.py")
FIXTURES_DIR = File.join(DIR, "fixtures")
RESOURCE_DIR = File.expand_path("../../lib/kabosu/resources", DIR)
CONFIG_PATH = File.join(RESOURCE_DIR, "sudachi.json")
MODES = %w[A B C].freeze
EDITION = ENV.fetch("KABOSU_DICT_EDITION", "core")

abort "SudachiPy venv missing. Run: test/parity/setup.sh" unless File.executable?(VENV_PYTHON)

entry = Kabosu::Dictionary.list.find { _1[:edition] == EDITION }
abort "No '#{EDITION}' dictionary installed. Run: rake kabosu:install[#{EDITION}]" unless entry

sudachipy_version = IO.popen([VENV_PYTHON, "-c", "import sudachipy; print(sudachipy.__version__)"], &:read).strip

FileUtils.mkdir_p(FIXTURES_DIR)

MODES.each do |mode|
  cmd = [VENV_PYTHON, DUMP_SCRIPT, ConformanceCorpus::PATH, entry[:path], RESOURCE_DIR, CONFIG_PATH, mode]
  output = IO.popen(cmd, &:read)
  abort "dump_sudachipy.py failed for mode #{mode}" unless $?.success?
  path = File.join(FIXTURES_DIR, "sudachipy_#{mode}.jsonl")
  File.write(path, output)
  puts "wrote #{File.basename(path)} (#{output.count("\n")} morphemes)"
end

meta = {
  "sudachipy_version" => sudachipy_version,
  "dict_edition" => EDITION,
  "dict_version" => entry[:version],
  "corpus_sha256" => ConformanceCorpus.sha256,
  "modes" => MODES
}
File.write(File.join(FIXTURES_DIR, "meta.json"), "#{JSON.pretty_generate(meta)}\n")
puts "wrote meta.json: #{meta.slice("sudachipy_version", "dict_edition", "dict_version")}"
