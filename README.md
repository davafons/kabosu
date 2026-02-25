<p align="center">
  <img src="logo.png" alt="Kabosu" width="150">
</p>

<h1 align="center">Kabosu</h1>

<p align="center">
  <a href="https://rubygems.org/gems/kabosu"><img src="https://img.shields.io/gem/v/kabosu" alt="Gem Version"></a>
  <a href="https://github.com/davafons/kabosu/actions/workflows/edge.yml"><img src="https://github.com/davafons/kabosu/actions/workflows/edge.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/davafons/kabosu/blob/main/LICENSE"><img src="https://img.shields.io/github/license/davafons/kabosu" alt="License"></a>
</p>

Ruby bindings for [sudachi.rs](https://github.com/WorksApplications/sudachi.rs), a Rust implementation of the [Sudachi](https://github.com/WorksApplications/Sudachi) Japanese morphological analyzer.

## Usage

```ruby
require "kabosu"

# Tokenize Japanese text
morphemes = Kabosu.tokenize("東京都に住んでいる")

morphemes.surfaces       # => ["東京都", "に", "住ん", "で", "いる"]
morphemes.readings       # => ["トウキョウト", "ニ", "スン", "デ", "イル"]
morphemes.dictionary_forms # => ["東京都", "に", "住む", "で", "居る"]

morphemes.each do |m|
  puts "#{m.surface}\t#{m.part_of_speech.join(',')}\t#{m.reading_form}"
end
```


## Installation

Requirements:
- Ruby >= 3.1
- Rust toolchain (for compiling the native extension)

Add to your Gemfile:

```ruby
gem "kabosu"
```

Then install and download a [Sudachi dictionary](https://github.com/WorksApplications/SudachiDict):

```sh
bundle install
bundle exec rake kabosu:install[small]  # or core, full
```

Dictionary editions (from smallest to largest): `small`, `core`, `full`. See the [SudachiDict documentation](https://github.com/WorksApplications/SudachiDict?tab=readme-ov-file#dictionary-types) for details on the differences between editions.

## Dictionary management

Rake tasks for managing Sudachi dictionaries:

```sh
rake kabosu:install[small]     # Install a dictionary (VERSION=YYYYMMDD for a specific version)
rake kabosu:list               # List installed dictionaries
rake kabosu:versions           # Show available versions from GitHub
rake kabosu:path               # Show path to best available dictionary
rake kabosu:remove[small]      # Remove a dictionary (VERSION=YYYYMMDD for a specific version)
```

Dictionaries are stored in `~/.kabosu/dict/` by default. Set `KABOSU_DICT_DIR` to customize.


### Tokenization modes

Sudachi provides three [split modes](https://github.com/WorksApplications/Sudachi?tab=readme-ov-file#the-modes-of-splitting):

| Mode | Description |
|------|-------------|
| `A` | Short units (most granular) |
| `B` | Middle units |
| `C` | Named entity units (default) |

```ruby
Kabosu.tokenize("東京都", mode: "A").surfaces  # => ["東京", "都"]
Kabosu.tokenize("東京都", mode: "C").surfaces  # => ["東京都"]
```

### Dictionary and Tokenizer API

For more control over dictionary and tokenizer configuration, create them directly:

```ruby
dict = Kabosu::Dictionary.new(dict: "/path/to/custom/dictionary")
tokenizer = dict.create("C")

morphemes = tokenizer.tokenize("国会議事堂前駅")
```

## Contributing

```sh
bundle install
bundle exec rake compile   # Build the native extension
bundle exec rake test      # Run tests
bundle exec rake           # Compile + test
```
