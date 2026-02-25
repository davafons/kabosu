#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Benchmark Kabosu (Ruby bindings) tokenization performance.
#
# Usage:
#   bundle exec ruby bench/bench_tokenize.rb
#
# Requires:
#   - Compiled native extension (bundle exec rake compile)
#   - A Sudachi dictionary installed (bundle exec rake kabosu:install[small])
#   - Fixture text (bench/setup)
#
require "benchmark"
require "kabosu"

FIXTURE = File.join(__dir__, "fixtures", "wagahai.txt")

unless File.exist?(FIXTURE)
  abort "Fixture not found. Run: bench/setup"
end

text = File.read(FIXTURE)
lines = text.lines.map(&:chomp).reject(&:empty?)

puts "Kabosu #{Kabosu::VERSION} benchmark"
puts "Input: #{File.basename(FIXTURE)} (#{text.bytesize} bytes, #{lines.size} lines)"
puts

# Warmup: ensure dictionary is loaded and cached
Kabosu.tokenize("テスト")

iterations = 10

Benchmark.bm(25) do |x|
  x.report("tokenize (full text)") do
    iterations.times { Kabosu.tokenize(text) }
  end

  x.report("tokenize (line-by-line)") do
    iterations.times do
      lines.each { |line| Kabosu.tokenize(line) }
    end
  end

  x.report("stateful (line-by-line)") do
    tok = Kabosu.batch_tokenizer(mode: "C")
    iterations.times do
      lines.each { |line| tok.tokenize(line) }
    end
  end

  x.report("mode A (full text)") do
    iterations.times { Kabosu.tokenize(text, mode: "A") }
  end

  x.report("mode B (full text)") do
    iterations.times { Kabosu.tokenize(text, mode: "B") }
  end
end

# Throughput summary
puts
elapsed = Benchmark.realtime { iterations.times { Kabosu.tokenize(text) } }
mb = (text.bytesize * iterations) / (1024.0 * 1024.0)
puts "Throughput: %.2f MB/s (mode C, %d iterations)" % [mb / elapsed, iterations]
