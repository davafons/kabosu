require_relative "lib/kabosu/version"

Gem::Specification.new do |spec|
  spec.name = "kabosu"
  spec.version = Kabosu::VERSION
  spec.authors = ["davafons"]
  spec.summary = "Ruby bindings for Sudachi Japanese morphological analyzer"
  spec.description = "Kabosu provides Ruby bindings for sudachi.rs, " \
                     "a Rust implementation of the Sudachi Japanese morphological analyzer."
  spec.homepage = "https://github.com/davafons/kabosu"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir[
    "lib/**/*.{rb,rake}",
    "lib/kabosu/resources/*.{json,def}",
    "ext/**/*.{rs,toml,rb}",
    "Cargo.toml",
    "Cargo.lock",
    "LICENSE",
    "README.md"
  ]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/kabosu/extconf.rb"]

  spec.add_dependency "rb_sys", "~> 0.9"
  spec.add_dependency "rubyzip", "~> 2.3"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "benchmark"
  spec.add_development_dependency "minitest", "~> 5.0"
end
