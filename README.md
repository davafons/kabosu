# Kabosu

Ruby bindings for [sudachi.rs](https://github.com/WorksApplications/sudachi.rs), a Rust implementation of the [Sudachi](https://github.com/WorksApplications/Sudachi) Japanese morphological analyzer.

## Requirements

- Ruby >= 3.1
- Rust toolchain (for compiling the native extension)

## Installation

Add to your Gemfile:

```ruby
gem "kabosu"
```

Then install and download a Sudachi dictionary:

```sh
bundle install
bundle exec rake kabosu:install[small]  # or core, full
```

Dictionary editions (from smallest to largest): `small`, `core`, `full`.

## Usage

```ruby
require "kabosu"

# Tokenize Japanese text (auto-discovers installed dictionary)
morphemes = Kabosu.tokenize("東京都に住んでいる")

morphemes.surfaces       # => ["東京都", "に", "住ん", "で", "いる"]
morphemes.readings       # => ["トウキョウト", "ニ", "スン", "デ", "イル"]
morphemes.dictionary_forms # => ["東京都", "に", "住む", "で", "居る"]

morphemes.each do |m|
  puts "#{m.surface}\t#{m.part_of_speech.join(',')}\t#{m.reading_form}"
end
```

### Tokenization modes

Sudachi provides three split modes:

| Mode | Description |
|------|-------------|
| `A` | Short units (most granular) |
| `B` | Middle units |
| `C` | Named entity units (default) |

```ruby
Kabosu.tokenize("東京都", mode: "A").surfaces  # => ["東京", "都"]
Kabosu.tokenize("東京都", mode: "C").surfaces  # => ["東京都"]
```

### Direct API

For more control, create a dictionary and tokenizer directly:

```ruby
dict = Kabosu::Dictionary.new
tokenizer = dict.create("C")
morphemes = tokenizer.tokenize("国会議事堂前駅")
```

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

## Development

```sh
bundle install
bundle exec rake compile   # Build the native extension
bundle exec rake test      # Run tests
bundle exec rake           # Compile + test
```

## License

MIT
