#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Benchmark Kabosu tokenization and sentence splitting separately.
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

dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
tok_c = dict.create(mode: :c)
tok_a = dict.create(mode: :a)
tok_b = dict.create(mode: :b)

# Warmup
tok_c.tokenize("テスト")

# Pre-split for tokenization-only benchmarks
sentences = Kabosu.split_sentences(text)

puts "── Sentence splitting ──"
puts
Benchmark.bm(20) do |x|
  x.report("split_sentences") do
    iterations.times { Kabosu.split_sentences(text) }
  end
end

puts
puts "── Tokenization ──"
puts
Benchmark.bm(20) do |x|
  x.report("mode C") do
    iterations.times { sentences.each { |s| tok_c.tokenize(s) } }
  end

  x.report("mode A") do
    iterations.times { sentences.each { |s| tok_a.tokenize(s) } }
  end

  x.report("mode B") do
    iterations.times { sentences.each { |s| tok_b.tokenize(s) } }
  end
end

puts
elapsed = Benchmark.realtime { iterations.times { sentences.each { |s| tok_c.tokenize(s) } } }
mb = (text.bytesize * iterations) / (1024.0 * 1024.0)
puts "Throughput: %.2f MB/s (mode C, %d iterations)" % [mb / elapsed, iterations]
