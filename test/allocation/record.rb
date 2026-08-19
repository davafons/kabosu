# frozen_string_literal: true

# Records the Tier 2 baselines. Driven by `rake alloc:record`; the assertions that
# read them live in test/allocation_test.rb.
require "kabosu"
require "yaml"
require_relative "measure"
require_relative "workloads"

dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
toks = Allocation::Workloads.tokenizers(dict)
edition = Kabosu::Dictionary.path.to_s[/small|core|full/] || "unknown"
path = File.expand_path("baselines.yml", __dir__)

recorded = File.exist?(path) ? YAML.load_file(path) : {}
recorded[edition] ||= {}

puts "dictionary edition: #{edition}   corpus lines: #{Allocation::Workloads.units}"
Allocation::Workloads.all.each do |name, body|
  objects, stable = Allocation.stable { body.call(toks) }
  abort "#{name} would not stabilise (#{objects}); refusing to record a number nobody can reproduce" unless stable

  was = recorded[edition][name]
  recorded[edition][name] = objects
  delta = was ? format(" (was %d, %+d)", was, objects - was) : " (new)"
  puts format("  %-16s %9d objects  %7.1f per line%s", name, objects, objects.to_f / Allocation::Workloads.units, delta)
end

File.write(path, <<~HEADER + recorded.to_yaml.sub(/\A---\n/, ""))
  # Recorded by `rake alloc:record`. One block per dictionary edition: `full`
  # segments differently from `core`, so their numbers are never compared and a
  # missing block is a skip rather than a failure.
  #
  # Every number is objects allocated with the GC held off, and they are EXACT —
  # a re-run on the same machine reproduces them to the object, which the suite
  # re-checks each run rather than assuming. Wall clock is deliberately absent
  # and must never gate anything.
  #
  # A number moving in EITHER direction stops the build. Up is a regression; down
  # is an improvement nobody has locked in yet, so re-record to hold the new floor.
HEADER
puts "wrote #{path}"
