use magnus::{prelude::*, Error, RArray, Ruby, Symbol, Value};
use sudachi::analysis::Mode;
use sudachi::dic::subset::InfoSubset;

use crate::errors::arg_error;

pub(crate) fn parse_mode(mode: Option<&str>) -> Result<Mode, Error> {
    match mode {
        None | Some("C") | Some("c") => Ok(Mode::C),
        Some("A") | Some("a") => Ok(Mode::A),
        Some("B") | Some("b") => Ok(Mode::B),
        Some(other) => Err(arg_error(format!(
            "invalid mode {other:?}; expected \"A\", \"B\", or \"C\""
        ))),
    }
}

pub(crate) fn parse_subset(value: Option<Value>) -> Result<InfoSubset, Error> {
    let Some(value) = value else {
        return Ok(InfoSubset::all());
    };

    if value.is_nil() {
        return Ok(InfoSubset::all());
    }

    let ary = RArray::try_convert(value)
        .map_err(|_| arg_error("fields must be an Array (of String/Symbol) or nil"))?;

    let mut subset = InfoSubset::empty();
    // SAFETY: we only read the array values while it is live on this stack frame.
    for &raw in unsafe { ary.as_slice() } {
        let name = if let Ok(sym) = Symbol::try_convert(raw) {
            sym.name()?.into_owned()
        } else if let Ok(s) = String::try_convert(raw) {
            s
        } else {
            return Err(arg_error("fields must contain only String or Symbol values"));
        };

        let normalized = name.to_ascii_lowercase();
        match subset_flag(&normalized) {
            Some(flag) => subset |= flag,
            None => {
                return Err(arg_error(format!(
                    "unknown field {name:?}; expected one of: surface, head_word_length, pos_id, normalized_form, dictionary_form, dictionary_form_word_id, reading_form, split_a, split_b, word_structure, synonym_group_id"
                )))
            }
        }
    }

    Ok(subset.normalize())
}

fn subset_flag(name: &str) -> Option<InfoSubset> {
    match name {
        "surface" => Some(InfoSubset::SURFACE),
        "head_word_length" => Some(InfoSubset::HEAD_WORD_LENGTH),
        "pos_id" => Some(InfoSubset::POS_ID),
        "normalized_form" | "normalized" => Some(InfoSubset::NORMALIZED_FORM),
        "dictionary_form" | "dictionary" | "dictionary_form_word_id" => {
            Some(InfoSubset::DIC_FORM_WORD_ID)
        }
        "reading_form" | "reading" => Some(InfoSubset::READING_FORM),
        "split_a" => Some(InfoSubset::SPLIT_A),
        "split_b" => Some(InfoSubset::SPLIT_B),
        "word_structure" => Some(InfoSubset::WORD_STRUCTURE),
        "synonym_group_id" | "synonym_group_ids" => Some(InfoSubset::SYNONYM_GROUP_ID),
        _ => None,
    }
}

pub(crate) fn subset_to_array(ruby: &Ruby, subset: InfoSubset) -> Result<RArray, Error> {
    let ary = ruby.ary_new();

    if subset.contains(InfoSubset::SURFACE) {
        ary.push(ruby.str_new("surface"))?;
    }
    if subset.contains(InfoSubset::HEAD_WORD_LENGTH) {
        ary.push(ruby.str_new("head_word_length"))?;
    }
    if subset.contains(InfoSubset::POS_ID) {
        ary.push(ruby.str_new("pos_id"))?;
    }
    if subset.contains(InfoSubset::NORMALIZED_FORM) {
        ary.push(ruby.str_new("normalized_form"))?;
    }
    if subset.contains(InfoSubset::DIC_FORM_WORD_ID) {
        ary.push(ruby.str_new("dictionary_form"))?;
        ary.push(ruby.str_new("dictionary_form_word_id"))?;
    }
    if subset.contains(InfoSubset::READING_FORM) {
        ary.push(ruby.str_new("reading_form"))?;
    }
    if subset.contains(InfoSubset::SPLIT_A) {
        ary.push(ruby.str_new("split_a"))?;
    }
    if subset.contains(InfoSubset::SPLIT_B) {
        ary.push(ruby.str_new("split_b"))?;
    }
    if subset.contains(InfoSubset::WORD_STRUCTURE) {
        ary.push(ruby.str_new("word_structure"))?;
    }
    if subset.contains(InfoSubset::SYNONYM_GROUP_ID) {
        ary.push(ruby.str_new("synonym_group_id"))?;
    }

    Ok(ary)
}

pub(crate) fn parse_user_dicts(value: Option<Value>) -> Result<Vec<String>, Error> {
    let Some(value) = value else {
        return Ok(Vec::new());
    };

    if value.is_nil() {
        return Ok(Vec::new());
    }

    let ary = RArray::try_convert(value)
        .map_err(|_| arg_error("user_dicts must be an Array (of String) or nil"))?;

    let mut user_dicts = Vec::with_capacity(ary.len());
    // SAFETY: we only read the array values while it is live on this stack frame.
    for &raw in unsafe { ary.as_slice() } {
        let path = String::try_convert(raw)
            .map_err(|_| arg_error("user_dicts must contain only String values"))?;
        user_dicts.push(path);
    }

    Ok(user_dicts)
}
