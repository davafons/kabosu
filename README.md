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

## Usage

```ruby
require "kabosu"

# Tokenize Japanese text (auto-discovers installed dictionary)
morphemes = Kabosu.tokenize("東京都に住んでいる")

# Bulk accessors for quick extraction
morphemes.surfaces          # => ["東京都", "に", "住ん", "で", "いる"]
morphemes.readings          # => ["トウキョウト", "ニ", "スン", "デ", "イル"]
morphemes.dictionary_forms  # => ["東京都", "に", "住む", "で", "居る"]

# Each morpheme exposes rich linguistic detail
morpheme = morphemes.first
morpheme.surface             # => "東京都"         - surface form (as it appears in text)
morpheme.part_of_speech      # => ["名詞", "固有名詞", "地名", "一般"] — part-of-speech tags
morpheme.part_of_speech_id   # => 5                - numeric POS id
morpheme.dictionary_form     # => "東京都"         - base/dictionary form
morpheme.normalized_form     # => "東京都"         - normalized form
morpheme.reading_form        # => "トウキョウト"   - phonetic reading
morpheme.oov?                # => false            - out-of-vocabulary?
morpheme.dictionary_id       # => 0                - source dictionary id
morpheme.word_id             # => 544373           - internal word id
morpheme.synonym_group_ids   # => []               - synonym group ids
morpheme.total_cost          # => 5765             - morphological analysis cost
morpheme.begin               # => 0                - start byte offset
morpheme.end                 # => 9                - end byte offset
morpheme.begin_c             # => 0                - start character offset
morpheme.end_c               # => 3                - end character offset
morpheme.system?             # => true             - from system dictionary?
morpheme.user?               # => false            - from user dictionary?
```

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

## Benchmarks

Kabosu ships with a benchmark suite that measures tokenization throughput and compares the Ruby bindings against raw [sudachi.rs](https://github.com/WorksApplications/sudachi.rs).

This benchmark uses [Wagahai wa Neko de Aru](https://www.aozora.gr.jp/cards/000148/card789.html) (I Am a Cat) by Natsume Soseki, sourced from [Aozora Bunko](https://www.aozora.gr.jp/) (public domain) as the source text. ~958 KB of Japanese prose, 2,256 lines as input.

### Results

Measured on an AMD Ryzen 7 5800X, `full` dictionary edition, Ruby 3.4, Rust 1.84:

| Scenario | Rust | Ruby | Ratio |
|---|---|---|---|
| Sentence-by-sentence (mode C) | 5.088s | 5.981s | 1.2x |
| Sentence-by-sentence (mode A) | 5.145s | 6.216s | 1.2x |
| Sentence-by-sentence (mode B) | 5.249s | 6.257s | 1.2x |
| **Throughput** | **1.80 MB/s** | **1.45 MB/s** | **1.2x** |

The Ruby bindings add ~20% overhead over raw Rust, primarily from FFI boundary crossings and Ruby object allocation for each morpheme.

To reproduce these results, run:

```sh
bundle exec ruby bench/start
```

### Profiling

To generate flamegraph SVGs alongside the benchmark:

```sh
bundle exec ruby bench/start --profile
```

This records both the Rust and Ruby runs with `perf` and produces interactive SVGs (`bench/flamegraph-rust.svg`, `bench/flamegraph-ruby.svg`). Open them in a browser to explore.

## Contributing

```sh
bundle install

bundle exec rake kabosu:install # Install Sudachi dictionary

bundle exec rake compile        # Build the native extension  
bundle exec rake test           # Run tests
bench/start                     # Run benchmarks
```
