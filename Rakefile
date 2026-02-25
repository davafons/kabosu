require "rake/extensiontask"
require "rake/testtask"

Rake::ExtensionTask.new("kabosu") do |ext|
  ext.lib_dir = "lib/kabosu"
  ext.source_pattern = "*.{rs,toml}"
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

load File.expand_path("lib/kabosu/tasks.rake", __dir__)
load File.expand_path("lib/kabosu/release.rake", __dir__)

task default: %i[compile test]
