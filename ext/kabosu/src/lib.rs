mod dictionary;
mod errors;
mod grouping;
mod morpheme;
mod nogvl;
mod parsing;
mod splitter;
mod token_batch;
mod tokenizer;

use magnus::{function, method, Error, Module, Object, Ruby};

use dictionary::RbDictionary;
use morpheme::RbMorpheme;
use splitter::{split_sentences, split_sentences_with_ranges};
use token_batch::RbTokenBatch;
use tokenizer::RbTokenizer;

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("Kabosu")?;

    // Internal sentence splitter APIs. Ruby wraps these with keywords.
    module.define_module_function("_split_sentences", function!(split_sentences, 3))?;
    module.define_module_function(
        "_split_sentences_with_ranges",
        function!(split_sentences_with_ranges, 3),
    )?;

    // Kabosu::Dictionary
    let dict_class = module.define_class("Dictionary", ruby.class_object())?;
    dict_class.define_singleton_method("new", function!(RbDictionary::new, 3))?;
    dict_class.define_method("lookup", method!(RbDictionary::lookup, 1))?;
    dict_class.define_method("create", method!(RbDictionary::create, 3))?;

    // Kabosu::TokenBatch (internal lazy token container)
    let batch_class = module.define_class("TokenBatch", ruby.class_object())?;
    batch_class.define_method("size", method!(RbTokenBatch::size, 0))?;
    batch_class.define_method("internal_cost", method!(RbTokenBatch::internal_cost, 0))?;
    batch_class.define_method("morpheme_at", method!(RbTokenBatch::morpheme_at, 1))?;
    batch_class.define_method("surfaces", method!(RbTokenBatch::surfaces, 0))?;
    batch_class.define_method("group_morphemes", method!(RbTokenBatch::group_morphemes, 0))?;

    // Kabosu::Tokenizer
    let tok_class = module.define_class("Tokenizer", ruby.class_object())?;
    tok_class.define_method("tokenize", method!(RbTokenizer::tokenize, 1))?;
    tok_class.define_method("mode", method!(RbTokenizer::mode, 0))?;
    tok_class.define_method("fields", method!(RbTokenizer::fields, 0))?;
    tok_class.define_method("debug?", method!(RbTokenizer::is_debug, 0))?;
    tok_class.define_method("internal_cost", method!(RbTokenizer::internal_cost, 0))?;

    // Kabosu::Morpheme
    let morph_class = module.define_class("Morpheme", ruby.class_object())?;
    morph_class.define_method("surface", method!(RbMorpheme::surface, 0))?;
    morph_class.define_method("part_of_speech", method!(RbMorpheme::part_of_speech, 0))?;
    morph_class.define_method(
        "part_of_speech_id",
        method!(RbMorpheme::part_of_speech_id, 0),
    )?;
    morph_class.define_method("dictionary_form", method!(RbMorpheme::dictionary_form, 0))?;
    morph_class.define_method("normalized_form", method!(RbMorpheme::normalized_form, 0))?;
    morph_class.define_method("reading_form", method!(RbMorpheme::reading_form, 0))?;
    morph_class.define_method("oov?", method!(RbMorpheme::is_oov, 0))?;
    morph_class.define_method("dictionary_id", method!(RbMorpheme::dictionary_id, 0))?;
    morph_class.define_method("word_id", method!(RbMorpheme::word_id, 0))?;
    morph_class.define_method(
        "dictionary_form_word_id",
        method!(RbMorpheme::dictionary_form_word_id, 0),
    )?;
    morph_class.define_method("head_word_length", method!(RbMorpheme::head_word_length, 0))?;
    morph_class.define_method("begin", method!(RbMorpheme::begin, 0))?;
    morph_class.define_method("end", method!(RbMorpheme::end, 0))?;
    morph_class.define_method("begin_c", method!(RbMorpheme::begin_c, 0))?;
    morph_class.define_method("end_c", method!(RbMorpheme::end_c, 0))?;
    morph_class.define_method(
        "synonym_group_ids",
        method!(RbMorpheme::synonym_group_ids, 0),
    )?;
    morph_class.define_method("a_unit_split", method!(RbMorpheme::a_unit_split, 0))?;
    morph_class.define_method("b_unit_split", method!(RbMorpheme::b_unit_split, 0))?;
    morph_class.define_method("word_structure", method!(RbMorpheme::word_structure, 0))?;
    morph_class.define_method("total_cost", method!(RbMorpheme::total_cost, 0))?;
    morph_class.define_method("system?", method!(RbMorpheme::is_system, 0))?;
    morph_class.define_method("user?", method!(RbMorpheme::is_user, 0))?;
    morph_class.define_method("split", method!(RbMorpheme::split, 3))?;
    morph_class.define_method("inspect", method!(RbMorpheme::inspect, 0))?;
    morph_class.define_method("to_s", method!(RbMorpheme::to_s, 0))?;

    Ok(())
}
