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
morpheme.head_word_length    # => 9                - bytes of the normalized index form
morpheme.a_unit_split        # => [123, 456]       - split-A word ids
morpheme.b_unit_split        # => []               - split-B word ids
morpheme.word_structure      # => [123, 456]       - word-structure ids
morpheme.c_unit_split        # => []               - split-C word ids (V1 dictionaries)
morpheme.user_data           # => ""               - free text from a user dictionary's user_data column
morpheme.total_cost          # => 5765             - morphological analysis cost
morpheme.begin               # => 0                - start byte offset
morpheme.end                 # => 9                - end byte offset
morpheme.begin_c             # => 0                - start character offset
morpheme.end_c               # => 3                - end character offset
morpheme.system?             # => true             - from system dictionary?
morpheme.user?               # => false            - from user dictionary?

# Split text into natural Japanese sentence boundaries
Kabosu.split_sentences("東京都に住んでいる。大阪も好きだ。")
# => ["東京都に住んでいる。", "大阪も好きだ。"]
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
bundle exec rake kabosu:install:small  # or :core, :full
```

Dictionary editions (from smallest to largest): `small`, `core`, `full`. See the [SudachiDict documentation](https://github.com/WorksApplications/SudachiDict?tab=readme-ov-file#dictionary-types) for details on the differences between editions.

kabosu 0.7 (sudachi.rs 0.7) reads only the V1 dictionary format: SudachiDict `20261015` or later.

## Upgrading from 0.6

sudachi.rs 0.7 changed the binary dictionary format, so a 0.6 setup needs three things:

1. **Reinstall the system dictionary.** Dictionaries installed by kabosu 0.6 are V0 and cannot be loaded. Run `rake kabosu:install` (or `install_if_missing`, which ignores V0 files), then drop the old ones with `rake kabosu:remove VERSION=...`. `rake kabosu:list` marks them.
2. **Rebuild user dictionaries** against that exact system dictionary: `rake kabosu:build_user_dict CSV=names.csv OUTPUT=names.dic` (or `Kabosu.build_user_dict`). A user dictionary now records which system dictionary it was built with, and loading it with a different one raises `Kabosu::DictionaryError`. The CSV uses the V1 column layout (see [Sudachi's user dictionary guide](https://github.com/WorksApplications/Sudachi/blob/develop/docs/user_dict.md)).
3. **Expect small tokenization differences.** sudachi.rs 0.7 aligned its lattice search, character-category handling and katakana OOV joining with Java Sudachi, so some inputs segment differently even with the same dictionary. Custom `char.def` files must replace `NOOOVBOW2` with `NOOOVBOW NOOOVEOW`.

Other visible changes: `Dictionary#lookup` normalizes the query first (`ｶﾎﾞｽ` finds カボス), joined numerals and katakana carry an OOV `word_id` instead of `4294967295`, and a custom config that names no `char.def`/`unk.def` falls back to the files built into sudachi.rs.

## Dictionary management

Rake tasks for managing Sudachi dictionaries:

```sh
rake kabosu:install:small       # Install a dictionary (VERSION=YYYYMMDD for a specific version)
rake kabosu:install_if_missing  # Same, but a no-op when a dictionary is already installed
rake kabosu:list                # List installed dictionaries
rake kabosu:versions            # Show available versions from GitHub
rake kabosu:path                # Show path to best available dictionary
rake kabosu:remove:small        # Remove a dictionary (VERSION=YYYYMMDD for a specific version)
```

Dictionaries are stored in `~/.kabosu/dict/` by default. Set `KABOSU_DICT_DIR` to customize — useful for pointing at a Docker volume so the dictionary persists across deployments.

In a Rails app, the rake tasks are auto-loaded via railtie — no manual `load` needed. For container entrypoints, `rake kabosu:install_if_missing` converges on the desired state without hitting the network on subsequent runs.

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

## Advanced Use Cases

```ruby
# Custom system dictionary + optional user dictionaries
dict = Kabosu::Dictionary.new(
  system_dict: "/path/to/custom/system.dic",
  user_dicts: ["/path/to/domain.dic", "/path/to/names.dic"]
)

# Create tokenizer with explicit mode/fields
tokenizer = dict.create(mode: :c, fields: %i[surface pos_id reading_form])

# Tokenize (returns MorphemeList; lazily hydrates morphemes)
list = tokenizer.tokenize("国会議事堂前駅")
list.surfaces
list.first.part_of_speech

# Dictionary prefix lookup (the query is normalized first, like tokenization)
dict.lookup("東京都").surfaces

# Morpheme split
m = tokenizer.tokenize("東京都").first
m.split(mode: :a).surfaces

# Sentence splitting
Kabosu.split_sentences("東京都に住んでいる。大阪も好きだ。", ranges: true)
Kabosu.split_sentences("長い文...", limit: 12, with_checker: true)
```

### Dictionary entries and forms (sudachi.rs 0.7)

```ruby
m = tokenizer.tokenize("住んでいた").first   # 住ん
m.dictionary_form_morpheme                   # the 住む entry itself: POS, reading, ids…
tokenizer.tokenize("附属").first.normalized_form_morpheme.surface # => "付属"
# A word that is its own form (and any OOV word) returns itself.

# Every entry in the loaded dictionaries, lazily (millions for `full`)
dict.entries.lazy.select(&:user?).first(10)

# Exact matches by scanning every entry, including ones not indexed for
# lookup. Slow on large dictionaries; prefer #lookup.
dict.lookup_all_entries("ｶﾎﾞｽ").surfaces     # => ["カボス"]

# Hand-made out-of-vocabulary morpheme; forms default to the surface
dict.oov_morpheme(m.part_of_speech_id, "ズィーガン", reading: "ジーガン")

# What tokenization actually sees after the input-text plugins
dict.normalize("ｶﾎﾞｽ ＡＢＣ コンピュータ〜〜") # => "カボス abc コンピューター"

# Compile a user dictionary against the installed system dictionary
Kabosu.build_user_dict("names.csv", output: "names.dic")
```

## Benchmarks

Kabosu ships with a benchmark suite that measures tokenization throughput and compares the Ruby bindings against raw [sudachi.rs](https://github.com/WorksApplications/sudachi.rs).

This benchmark uses [Wagahai wa Neko de Aru](https://www.aozora.gr.jp/cards/000148/card789.html) (I Am a Cat) by Natsume Soseki, sourced from [Aozora Bunko](https://www.aozora.gr.jp/) (public domain) as the source text. ~958 KB of Japanese prose, 2,256 lines as input.

### Results

Measured on an AMD Ryzen 7 5800X, `full` dictionary edition, Ruby 3.4, Rust 1.84:

Single-thread (10 iterations):

| Scenario | Rust | Ruby | Ratio |
|---|---|---|---|
| split_sentences | 1.550s | 1.615s | 1.0x |
| tokenize (mode C) | 3.148s | 3.395s | 1.1x |
| tokenize (mode A) | 3.227s | 3.525s | 1.1x |
| tokenize (mode B) | 3.226s | 3.582s | 1.1x |
| **Throughput** | **2.94 MB/s** | **2.69 MB/s** | **1.1x** |

Multithread (8 threads x 20,000 requests):

| Scenario | Rust | Ruby | Ratio |
|---|---|---|---|
| rails-style shared tokenizer | 1.475s | 2.101s | 1.4x |
| tokenizer per thread | 1.381s | 2.154s | 1.6x |
| **Throughput ST** | **20.44 MB/s** | **14.35 MB/s** | **1.4x** |
| **Throughput PT** | **21.84 MB/s** | **14.00 MB/s** | **1.6x** |

Notes:
- `shared tokenizer` matches Rails-style access where all request threads call one tokenizer instance.
- `per thread` creates one tokenizer per worker thread.
- Ratios are `Ruby / Rust`, and values vary by CPU, Ruby version, and dictionary edition.

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
