namespace :release do
  desc "Bump version. Usage: rake release:bump[1.2.3]"
  task :bump, [:version] do |_t, args|
    version = args[:version]
    abort "Usage: rake release:bump[1.2.3]" unless version&.match?(/\A\d+\.\d+\.\d+\z/)

    # Update lib/kabosu/version.rb
    version_file = File.expand_path("version.rb", __dir__)
    content = File.read(version_file)
    new_content = content.sub(/VERSION = ".*"/, %(VERSION = "#{version}"))
    File.write(version_file, new_content)
    puts "Updated #{version_file}"

    # Update ext/kabosu/Cargo.toml
    cargo_file = File.expand_path("../../ext/kabosu/Cargo.toml", __dir__)
    content = File.read(cargo_file)
    new_content = content.sub(/^version = ".*"/, %(version = "#{version}"))
    File.write(cargo_file, new_content)
    puts "Updated #{cargo_file}"

    puts "\nVersion bumped to #{version}"
    puts "Next steps:"
    puts "  jj commit -m 'Bump version to #{version}'"
    puts "  jj tag set v#{version}"
    puts "  jj git push --all"
  end

  desc "Build the gem"
  task :build do
    sh "gem build kabosu.gemspec"
  end

  desc "Build and push the gem to RubyGems"
  task push: :build do
    gemfile = Dir["kabosu-*.gem"].max_by { |f| File.mtime(f) }
    abort "No .gem file found" unless gemfile
    sh "gem push #{gemfile}"
  end
end
