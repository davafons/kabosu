<p align="center">
  <img src="logo.png" alt="Kabosu" width="150">
</p>

<h1 align="center">Kabosu</h1>

<p align="center">
  <a href="https://rubygems.org/gems/kabosu"><img src="https://img.shields.io/gem/v/kabosu" alt="Gem Version"></a>
  <a href="https://github.com/davafons/kabosu/actions/workflows/edge.yml"><img src="https://github.com/davafons/kabosu/actions/workflows/edge.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/davafons/kabosu/blob/main/LICENSE"><img src="https://img.shields.io/github/license/davafons/kabosu" alt="License"></a>
  <a href="https://rubygems.org/gems/kabosu"><img src="https://img.shields.io/gem/dt/kabosu" alt="Downloads"></a>
</p>

Ruby bindings for [sudachi.rs](https://github.com/WorksApplications/sudachi.rs), a Rust implementation of the [Sudachi](https://github.com/WorksApplications/Sudachi) Japanese morphological analyzer.

## Usage

```ruby
require "kabosu"

# Explicit dictionary + tokenizer lifecycle
dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
tokenizer = dict.create(mode: :c)

# Tokenize Japanese text
morphemes = Kabosu.tokenize("東京都に住んでいる", tokenizer: tokenizer)

# Bulk accessors for quick extraction
morphemes.surfaces          # => ["東京都", "に", "住ん", "で", "いる"]
morphemes.readings          # => ["トウキョウト", "ニ", "スン", "デ", "イル"]
morphemes.dictionary_forms  # => ["東京都", "に", "住む", "で", "居る"]

# Each morpheme exposes rich linguistic detail
morpheme = morphemes.first
morpheme.surface             # => "東京都"          - surface form (as it appears in text)
morpheme.part_of_speech      # => ["名詞", "固有名詞", "地名", "一般"] — part-of-speech tags
morpheme.part_of_speech_id   # => 5                - numeric POS id
morpheme.dictionary_form     # => "東京都"          - base/dictionary form
morpheme.normalized_form     # => "東京都"          - normalized form
morpheme.reading_form        # => "トウキョウト"     - phonetic reading
morpheme.oov?                # => false            - out-of-vocabulary?
morpheme.dictionary_id       # => 0                - source dictionary id
morpheme.word_id             # => 544373           - internal word id
morpheme.synonym_group_ids   # => []               - synonym group ids
morpheme.dictionary_form_word_id # => -1           - dictionary-form word id
morpheme.head_word_length    # => 3                - head word length in codepoints
morpheme.a_unit_split        # => [123, 456]       - split-A word ids
morpheme.b_unit_split        # => []               - split-B word ids
morpheme.word_structure      # => [123, 456]       - word-structure ids
morpheme.total_cost          # => 5765             - morphological analysis cost
morpheme.begin               # => 0                - start byte offset
morpheme.end                 # => 9                - end byte offset
morpheme.begin_c             # => 0                - start character offset
morpheme.end_c               # => 3                - end character offset
morpheme.system?             # => true             - from system dictionary?
morpheme.user?               # => false            - from user dictionary?
```

## Installation

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

## Tokenization modes

Sudachi provides three [split modes](https://github.com/WorksApplications/Sudachi?tab=readme-ov-file#the-modes-of-splitting):

| Mode | Description |
|------|-------------|
| `A` | Short units (most granular) |
| `B` | Middle units |
| `C` | Named entity units (default) |

```ruby
dict = Kabosu::Dictionary.new(system_dict: Kabosu::Dictionary.path)
tok_a = dict.create(mode: :a)
tok_c = dict.create(mode: :c)
tok_a.tokenize("東京都").surfaces  # => ["東京", "都"]
tok_c.tokenize("東京都").surfaces  # => ["東京都"]
```

Modes are symbols only (`:a`, `:b`, `:c` or `Kabosu::MODE_A/B/C`).
Invalid modes now raise `ArgumentError` (for example, `"A"`).

## Dictionary and Tokenizer Internal API

For more control over dictionary and tokenizer configuration, create them directly:

```ruby
dict = Kabosu::Dictionary.new(
  system_dict: "/path/to/custom/system.dic",
  user_dicts: ["/path/to/domain.dic", "/path/to/names.dic"]
)
tokenizer = dict.create(mode: :c, fields: %i[surface pos_id reading_form])

morphemes = tokenizer.tokenize("国会議事堂前駅")
# MorphemeList is lazy: morphemes are hydrated on first indexed/iterated access.
# surfaces uses a fast path and does not force full morpheme hydration.
morphemes.surfaces
morphemes.first.part_of_speech

# Lexicon lookup (prefix matches from position 0), returns MorphemeList
dict.lookup("東京都").surfaces

# Morpheme split returns MorphemeList
m = tokenizer.tokenize("東京都").first
m.split(mode: :a).surfaces

# Native bulk extraction helpers (fewer Ruby<->Rust crossings)
tokenizer.tokenize_surfaces("東京都に住んでいる")
tokenizer.tokenize_readings("東京都に住んでいる")
tokenizer.tokenize_dictionary_forms("東京都に住んでいる")
tokenizer.tokenize_normalized_forms("東京都に住んでいる")

# Sentence splitting options
Kabosu.split_sentences("東京都に住んでいる。大阪も好きだ。", ranges: true)
Kabosu.split_sentences("長い文...", limit: 12, with_checker: true)

# ranges: true returns SentenceRange objects
ranges = Kabosu.split_sentences("東京都に住んでいる。", ranges: true)
ranges.first.start
ranges.first.end
ranges.first.text
```

Dictionary initialization failures raise typed errors:
- `Kabosu::ConfigError` for configuration issues
- `Kabosu::DictionaryError` for dictionary loading issues

Runtime failures in analysis APIs are also typed:
- `Kabosu::TokenizationError` for tokenization/split failures
- `Kabosu::SentenceSplitError` for sentence splitter failures
- `Kabosu::LookupError` for dictionary lookup failures

## Public API Contract

| API | Parameters | Return | Notes |
|---|---|---|---|
| `Kabosu::Dictionary.new` | `config: String?`, `system_dict: String?`, `user_dicts: Array<String>?` | `Kabosu::Dictionary` | One of `config` or `system_dict` is required |
| `Dictionary#create` | `mode: :a|:b|:c`, `fields: Array<String\|Symbol>?`, `debug: bool`, `projection: nil` | `Kabosu::Tokenizer` | Unknown kwargs raise `ArgumentError`; `projection` currently raises `NotImplementedError` |
| `Dictionary#lookup` | `text: String` | `Kabosu::MorphemeList` | Prefix lookup from byte offset 0 |
| `Tokenizer#tokenize` | `text: String` | `Kabosu::MorphemeList` | Lazy morpheme hydration; raises `Kabosu::TokenizationError` on native failures |
| `Tokenizer#tokenize_surfaces/readings/dictionary_forms/normalized_forms` | `text: String` | `Array<String>` | Raises `Kabosu::TokenizationError` on native failures |
| `Morpheme#split` | `mode: :a|:b|:c`, `add_single: bool` | `Kabosu::MorphemeList` | Standardized with `tokenize` return type |
| `Kabosu.split_sentences` | `text: String`, `limit: Integer?`, `with_checker: bool`, `ranges: bool`, `dictionary: String?` | `Array<String>` or `Array<Kabosu::SentenceRange>` | `limit` must be `>= 1` |
| `Kabosu.tokenize` | `text: String`, `tokenizer: Kabosu::Tokenizer` | `Kabosu::MorphemeList` | No hidden global tokenizer cache |

## Benchmarks

Kabosu ships with a benchmark suite that measures tokenization throughput and compares the Ruby bindings against raw [sudachi.rs](https://github.com/WorksApplications/sudachi.rs).

This benchmark uses [Wagahai wa Neko de Aru](https://www.aozora.gr.jp/cards/000148/card789.html) (I Am a Cat) by Natsume Soseki, sourced from [Aozora Bunko](https://www.aozora.gr.jp/) (public domain) as the source text. ~958 KB of Japanese prose, 2,256 lines as input.

### Results

Measured on an AMD Ryzen 7 5800X, `full` dictionary edition, Ruby 3.4, Rust 1.84:

| Scenario | Rust | Ruby | Ratio |
|---|---|---|---|
| split_sentences | 1.597s | 1.677s | 1.0x |
| tokenize (mode C) | 3.274s | 4.034s | 1.2x |
| tokenize (mode A) | 3.429s | 4.273s | 1.2x |
| tokenize (mode B) | 3.465s | 4.297s | 1.2x |
| **Throughput** | **2.66 MB/s** | **2.18 MB/s** | **1.2x** |

The Ruby bindings add ~20% overhead over raw Rust, primarily from FFI boundary crossings and Ruby object allocation for each morpheme.

To reproduce these results, run:

```sh
bundle exec ruby bench/start
```

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
