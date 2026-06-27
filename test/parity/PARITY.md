# kabosu ↔ SudachiPy parity

How close are kabosu's Ruby bindings to the official [SudachiPy](https://github.com/WorksApplications/SudachiPy)
Python bindings? Both wrap the same `sudachi.rs` core (kabosu via magnus, SudachiPy
via PyO3), so this measures the binding layer, not the analyzer.

`test/parity_test.rb` proves the claim mechanically: it runs the shared corpus
through kabosu and through SudachiPy **pointed at the same dictionary, config,
and resources**, and asserts identical values for every field both expose. As of
sudachi.rs / SudachiPy **v0.6.11**, dictionary `20260116` (core): **all 5219
field assertions across modes A/B/C pass — zero value divergences.**

The bindings are therefore *output-identical*. What differs is API surface and
ergonomics.

## Morpheme: field-by-field

| Concept | SudachiPy | kabosu | Values agree? |
|---|---|---|---|
| Surface | `surface()` | `surface` | ✅ verified |
| Part of speech (6-tuple) | `part_of_speech()` | `part_of_speech` | ✅ verified |
| POS id | `part_of_speech_id()` | `part_of_speech_id` | ✅ verified |
| Dictionary (base) form | `dictionary_form()` | `dictionary_form` | ✅ verified |
| Normalized form | `normalized_form()` | `normalized_form` | ✅ verified |
| Reading form | `reading_form()` | `reading_form` | ✅ verified |
| Out-of-vocabulary | `is_oov()` | `oov?` | ✅ verified |
| Dictionary id | `dictionary_id()` | `dictionary_id` | ✅ verified |
| Word id | `word_id()` | `word_id` | ✅ verified |
| Synonym group ids | `synonym_group_ids()` | `synonym_group_ids` | ✅ verified |
| **Start offset (chars)** | `begin()` | `begin_c` | ✅ verified (renamed) |
| **End offset (chars)** | `end()` | `end_c` | ✅ verified (renamed) |
| Split into sub-units | `split(mode)` | `split(mode:)` | ✅ equivalent |
| Head word length | `get_word_info().head_word_length` | `head_word_length` | ✅ verified (non-OOV) |
| Dictionary-form word id | `get_word_info().dictionary_form_word_id` | `dictionary_form_word_id` | ✅ verified (non-OOV) |
| A-unit split ids | `get_word_info().a_unit_split` | `a_unit_split` | ✅ verified (non-OOV) |
| B-unit split ids | `get_word_info().b_unit_split` | `b_unit_split` | ✅ verified (non-OOV) |
| Word structure ids | `get_word_info().word_structure` | `word_structure` | ✅ verified (non-OOV) |

### Differences

**Offset semantics (the one gotcha).** SudachiPy's `begin()`/`end()` are
**character** offsets. kabosu names those `begin_c`/`end_c` and *additionally*
exposes **byte** offsets as `begin`/`end`. Code ported from SudachiPy that calls
`begin()`/`end()` must use `begin_c`/`end_c` in kabosu, not `begin`/`end`.

**WordInfo is flattened.** SudachiPy returns a separate `get_word_info()` object
(and warns it is "raw"). kabosu lifts those fields directly onto the morpheme
(`head_word_length`, `a_unit_split`, …), so no second call is needed.

**kabosu-only accessors:** `begin`/`end` (byte offsets), `total_cost`,
`system?`, `user?`.

**SudachiPy-only accessors:** `raw_surface()` (surface before input-text-plugin
rewriting), and the explicit `get_word_info()` object.

## Dictionary / Tokenizer level

| Concept | SudachiPy | kabosu |
|---|---|---|
| Build a dictionary | `Dictionary(config_path=, resource_dir=, dict=)` | `Kabosu::Dictionary.new(config:, system_dict:, user_dicts:)` |
| Create a tokenizer | `dict.create(mode=SplitMode.C)` | `dict.create(mode: :c)` |
| Tokenize | `tokenizer.tokenize(text, mode)` — mode overridable per call | `tokenizer.tokenize(text)` — mode fixed at create time |
| Split mode | `SplitMode.A/B/C` | `:a`/`:b`/`:c` (or `Kabosu::MODE_A/B/C`) |
| POS matcher | `dict.pos_matcher(...)` | `Kabosu::PosMatcher` |
| Prefix lookup | (not exposed) | `dict.lookup(text)` |

**kabosu adds**, with no SudachiPy equivalent: a `MorphemeList` with bulk
accessors (`surfaces`, `readings`, `dictionary_forms`, `normalized_forms`,
`total_costs`), POS filtering (`select_pos`/`reject_pos`), jpdb-style
`group_morphemes`, sentence splitting (`Kabosu.split_sentences`), and built-in
dictionary management (`Kabosu::Dictionary.install/list/path`).

**Notable behavioral difference:** SudachiPy lets you pass the split mode to
`tokenize(text, mode)` per call; kabosu fixes the mode when the tokenizer is
created via `dict.create(mode:)`. Per-morpheme `split(mode:)` is available in
both.

## Reproducing

```sh
test/parity/setup.sh                  # create venv, pip install sudachipy==0.6.11
ruby -Ilib test/parity/generate.rb    # regenerate fixtures from SudachiPy
bundle exec ruby -Ilib -Itest test/parity_test.rb
```
