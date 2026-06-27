// Reference morpheme dumper built directly on sudachi.rs.
//
// Usage: reference_dump <corpus_path> <dict_path> <mode A|B|C>
//
// Emits JSON Lines on stdout: one object per morpheme, in tokenization order,
// tagged with the 0-based index of its source line within the corpus (comments
// and blank lines excluded). Field extraction mirrors
// ext/kabosu/src/morpheme.rs exactly — including the OOV / negative-dictionary
// fallbacks kabosu applies to word-info fields — so that a field-by-field
// equality check against kabosu is a true conformance test.

use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::Arc;

use serde_json::{json, Value};
use sudachi::analysis::morpheme::Morpheme as SudachiMorpheme;
use sudachi::analysis::stateless_tokenizer::{DictionaryAccess, StatelessTokenizer};
use sudachi::analysis::{Mode, Tokenize};
use sudachi::config::Config;
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::dic::word_id::WordId;

fn parse_mode(s: &str) -> Mode {
    match s {
        "A" | "a" => Mode::A,
        "B" | "b" => Mode::B,
        "C" | "c" => Mode::C,
        other => panic!("invalid mode {other:?}; expected A, B, or C"),
    }
}

// Word-info fields, mirroring kabosu's LazyWordFields + resolve_word_fields.
struct WordFields {
    synonym_group_ids: Vec<u32>,
    dictionary_form_word_id: i32,
    head_word_length: usize,
    a_unit_split: Vec<u32>,
    b_unit_split: Vec<u32>,
    word_structure: Vec<u32>,
}

fn resolve_word_fields<T: DictionaryAccess>(
    dict: &T,
    surface: &str,
    is_oov: bool,
    dictionary_id: i32,
    word_id_raw: u32,
) -> WordFields {
    let fallback = || WordFields {
        synonym_group_ids: Vec::new(),
        dictionary_form_word_id: -1,
        head_word_length: surface.chars().count(),
        a_unit_split: Vec::new(),
        b_unit_split: Vec::new(),
        word_structure: Vec::new(),
    };

    if is_oov || dictionary_id < 0 {
        return fallback();
    }

    let wid = WordId::from_raw(word_id_raw);
    match dict.lexicon().get_word_info(wid) {
        Ok(info) => WordFields {
            synonym_group_ids: info.synonym_group_ids().to_vec(),
            dictionary_form_word_id: info.dictionary_form_word_id(),
            head_word_length: info.head_word_length(),
            a_unit_split: info.a_unit_split().iter().map(WordId::as_raw).collect(),
            b_unit_split: info.b_unit_split().iter().map(WordId::as_raw).collect(),
            word_structure: info.word_structure().iter().map(WordId::as_raw).collect(),
        },
        Err(_) => fallback(),
    }
}

fn morpheme_to_json<T: DictionaryAccess>(
    dict: &T,
    line: usize,
    index: usize,
    m: &SudachiMorpheme<'_, T>,
) -> Value {
    let surface = m.surface().to_string();
    let is_oov = m.is_oov();
    let dictionary_id = m.dictionary_id();
    let word_id_raw = m.word_id().as_raw();

    let wf = resolve_word_fields(dict, &surface, is_oov, dictionary_id, word_id_raw);

    json!({
        "line": line,
        "index": index,
        "surface": surface,
        "part_of_speech": m.part_of_speech().to_vec(),
        "part_of_speech_id": m.part_of_speech_id(),
        "dictionary_form": m.dictionary_form(),
        "normalized_form": m.normalized_form(),
        "reading_form": m.reading_form(),
        "oov": is_oov,
        "dictionary_id": dictionary_id,
        "word_id": word_id_raw,
        "system": m.word_id().is_system(),
        "user": m.word_id().is_user(),
        "begin": m.begin(),
        "end": m.end(),
        "begin_c": m.begin_c(),
        "end_c": m.end_c(),
        "total_cost": m.total_cost(),
        "synonym_group_ids": wf.synonym_group_ids,
        "dictionary_form_word_id": wf.dictionary_form_word_id,
        "head_word_length": wf.head_word_length,
        "a_unit_split": wf.a_unit_split,
        "b_unit_split": wf.b_unit_split,
        "word_structure": wf.word_structure,
    })
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!("Usage: reference_dump <corpus_path> <dict_path> <mode A|B|C>");
        std::process::exit(1);
    }

    let corpus_path = &args[1];
    let dict_path = PathBuf::from(&args[2]);
    let mode = parse_mode(&args[3]);

    let text = fs::read_to_string(corpus_path).expect("failed to read corpus");
    // `lines()` already strips the terminator. Skip blank and comment lines so
    // the surviving line indices line up with the Ruby side reading the same file.
    let inputs: Vec<&str> = text
        .lines()
        .filter(|l| !l.trim().is_empty() && !l.trim_start().starts_with('#'))
        .collect();

    let cfg = Config::new(None, None, Some(dict_path)).expect("failed to build config");
    let dict = Arc::new(JapaneseDictionary::from_cfg(&cfg).expect("failed to load dictionary"));
    let tokenizer = StatelessTokenizer::new(dict.clone());

    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());

    for (line, input) in inputs.iter().enumerate() {
        let morphemes = tokenizer
            .tokenize(input, mode, false)
            .expect("tokenization failed");
        for (index, m) in morphemes.iter().enumerate() {
            let value = morpheme_to_json(&dict, line, index, &m);
            writeln!(out, "{}", value).expect("write failed");
        }
    }
    out.flush().expect("flush failed");
}
