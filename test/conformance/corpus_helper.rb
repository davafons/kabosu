require "digest"

# Shared corpus reader for the conformance and parity suites. The filtering
# rules here MUST match the Rust reference dumper (test/conformance/reference)
# and the SudachiPy harness (test/parity): skip blank lines and lines whose
# first non-space character is '#'. The surviving order defines the `line`
# index that every backend tags its morphemes with.
module ConformanceCorpus
  PATH = File.expand_path("corpus.txt", __dir__).freeze

  module_function

  def lines(path = PATH)
    File.readlines(path, chomp: true).filter_map do |raw|
      stripped = raw.strip
      next if stripped.empty?
      next if stripped.start_with?("#")

      raw
    end
  end

  def sha256(path = PATH)
    Digest::SHA256.hexdigest(File.binread(path))
  end
end
