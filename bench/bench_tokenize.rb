#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Benchmark Kabosu tokenization (sentence-by-sentence, all modes).
#
# Usage:
#   bundle exec ruby bench/bench_tokenize.rb
#
$stdout.sync = true

require "benchmark"
require "kabosu"

FIXTURE = File.join(__dir__, "fixtures", "wagahai.txt")

unless File.exist?(FIXTURE)
  abort "Fixture not found. Run: bench/setup"
end

text = File.read(FIXTURE)
iterations = 10

puts "Kabosu #{Kabosu::VERSION} benchmark"
puts "Input: #{File.basename(FIXTURE)} (#{text.bytesize} bytes)"
puts

# Warmup
Kabosu.tokenize("テスト")

tok_c = Kabosu.batch_tokenizer(mode: "C")
tok_a = Kabosu.batch_tokenizer(mode: "A")
tok_b = Kabosu.batch_tokenizer(mode: "B")

Benchmark.bm(20) do |x|
  x.report("mode C (sentences)") do
    iterations.times { tok_c.tokenize_sentences(text) }
  end

  x.report("mode A (sentences)") do
    iterations.times { tok_a.tokenize_sentences(text) }
  end

  x.report("mode B (sentences)") do
    iterations.times { tok_b.tokenize_sentences(text) }
  end
end

puts
elapsed = Benchmark.realtime { iterations.times { tok_c.tokenize_sentences(text) } }
mb = (text.bytesize * iterations) / (1024.0 * 1024.0)
puts "Throughput: %.2f MB/s (mode C, %d iterations)" % [mb / elapsed, iterations]
