#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Benchmark multithread tokenization throughput in Ruby.
#
# Usage:
#   bundle exec ruby bench/bench_multithread.rb [threads] [requests_per_thread]
#
$stdout.sync = true

require "benchmark"
require "kabosu"

FIXTURE = File.join(__dir__, "fixtures", "wagahai.txt")

unless File.exist?(FIXTURE)
  abort "Fixture not found. Run: bench/setup"
end

threads = (ARGV[0] || ENV["THREADS"] || "8").to_i
requests_per_thread = (ARGV[1] || ENV["REQUESTS_PER_THREAD"] || "20000").to_i

if threads <= 0 || requests_per_thread <= 0
  abort "threads and requests_per_thread must be positive integers"
end

text = File.read(FIXTURE)
dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
sentences = Kabosu.split_sentences(text).reject(&:empty?).freeze

if sentences.empty?
  abort "No sentences extracted from fixture"
end

# Warmup
dict.create(mode: :c).tokenize("テスト")

puts "Kabosu #{Kabosu::VERSION} multithread benchmark"
puts "Input: #{File.basename(FIXTURE)} (#{text.bytesize} bytes)"
puts "Threads: #{threads}, requests/thread: #{requests_per_thread}"
puts "Scenario shared tok: one tokenizer shared by all threads (Rails-style)"
puts "Scenario per-thread tok: one tokenizer per worker thread"
puts

elapsed_shared = Benchmark.realtime do
  shared = dict.create(mode: :c)
  workers = Array.new(threads) do |tid|
    Thread.new do
      bytes = 0
      len = sentences.length

      requests_per_thread.times do |i|
        sentence = sentences[(tid + i * 7919) % len]
        Kabosu.tokenize(sentence, tokenizer: shared)
        bytes += sentence.bytesize
      end

      bytes
    end
  end

  @total_bytes_shared = workers.sum(&:value)
end

elapsed_per_thread = Benchmark.realtime do
  workers = Array.new(threads) do |tid|
    Thread.new do
      tokenizer = dict.create(mode: :c)
      bytes = 0
      len = sentences.length

      requests_per_thread.times do |i|
        sentence = sentences[(tid + i * 7919) % len]
        tokenizer.tokenize(sentence)
        bytes += sentence.bytesize
      end

      bytes
    end
  end

  @total_bytes_per_thread = workers.sum(&:value)
end

total_requests = threads * requests_per_thread
mb_shared = @total_bytes_shared / (1024.0 * 1024.0)
mb_per_thread = @total_bytes_per_thread / (1024.0 * 1024.0)

puts "shared tok:      %8.3fs  (%d threads x %d req)" % [elapsed_shared, threads, requests_per_thread]
puts "Throughput ST: %.2f MB/s (Kabosu.tokenize shared tokenizer)" % [mb_shared / elapsed_shared]
puts "per-thread tok:  %8.3fs  (%d threads x %d req)" % [elapsed_per_thread, threads, requests_per_thread]
puts "Throughput PT: %.2f MB/s (tokenizer per thread)" % [mb_per_thread / elapsed_per_thread]
puts "Total requests: %d" % [total_requests]
