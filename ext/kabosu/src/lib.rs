use magnus::{function, method, prelude::*, Error, RArray, Ruby, Value};
use std::cell::{Cell, RefCell};
use std::sync::Arc;
use sudachi::analysis::stateful_tokenizer::StatefulTokenizer;
use sudachi::analysis::stateless_tokenizer::StatelessTokenizer;
use sudachi::analysis::{Mode, Tokenize};
use sudachi::config::Config;
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::prelude::MorphemeList;
use sudachi::sentence_splitter::{SentenceSplitter, SplitSentences};

fn sudachi_error(e: impl std::fmt::Display) -> Error {
    Error::new(
        Ruby::get().unwrap().exception_runtime_error(),
        e.to_string(),
    )
}

// ---------- Dictionary ----------

#[magnus::wrap(class = "Kabosu::Dictionary")]
struct RbDictionary {
    inner: Arc<JapaneseDictionary>,
}

impl RbDictionary {
    fn new(ruby: &Ruby, args: &[Value]) -> Result<Self, Error> {
        let (config_path, dict_path): (Option<String>, Option<String>) = match args.len() {
            0 => (None, None),
            1 => (<Option<String>>::try_convert(args[0])?, None),
            2 => (
                <Option<String>>::try_convert(args[0])?,
                <Option<String>>::try_convert(args[1])?,
            ),
            _ => {
                return Err(Error::new(
                    ruby.exception_arg_error(),
                    format!(
                        "wrong number of arguments (given {}, expected 0..2)",
                        args.len()
                    ),
                ))
            }
        };

        let cfg = match (&config_path, &dict_path) {
            (None, None) => Config::new(None, None, None).map_err(sudachi_error)?,
            (None, Some(dict)) => {
                Config::new(None, None, Some(dict.into())).map_err(sudachi_error)?
            }
            (Some(cfg_path), None) => {
                Config::new(Some(cfg_path.into()), None, None).map_err(sudachi_error)?
            }
            (Some(cfg_path), Some(dict)) => {
                Config::new(Some(cfg_path.into()), None, Some(dict.into()))
                    .map_err(sudachi_error)?
            }
        };

        let dict = JapaneseDictionary::from_cfg(&cfg).map_err(sudachi_error)?;

        Ok(Self {
            inner: Arc::new(dict),
        })
    }

    fn create(&self, mode: Option<String>) -> RbTokenizer {
        let mode = parse_mode(mode.as_deref());
        RbTokenizer {
            dict: self.inner.clone(),
            mode,
            debug: Cell::new(false),
            last_internal_cost: Cell::new(0),
        }
    }

    fn create_stateful(&self, mode: Option<String>) -> RbStatefulTokenizer {
        let mode = parse_mode(mode.as_deref());
        let tokenizer = StatefulTokenizer::new(self.inner.clone(), mode);
        RbStatefulTokenizer {
            dict: self.inner.clone(),
            inner: RefCell::new(tokenizer),
            mode,
            debug: Cell::new(false),
            last_internal_cost: Cell::new(0),
        }
    }
}

// ---------- Tokenizer ----------

#[magnus::wrap(class = "Kabosu::Tokenizer")]
struct RbTokenizer {
    dict: Arc<JapaneseDictionary>,
    mode: Mode,
    debug: Cell<bool>,
    last_internal_cost: Cell<i32>,
}

impl RbTokenizer {
    fn tokenize(&self, text: String) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let tokenizer = StatelessTokenizer::new(&*self.dict);
        let morphemes = tokenizer
            .tokenize(&text, self.mode, self.debug.get())
            .map_err(sudachi_error)?;

        self.last_internal_cost.set(morphemes.get_internal_cost());

        let ary = ruby.ary_new_capa(morphemes.len());
        for i in 0..morphemes.len() {
            let m = morphemes.get(i);
            let wid = m.word_id();
            let rb_m = RbMorpheme {
                surface: m.surface().to_string(),
                pos: m.part_of_speech().iter().map(|s| s.to_string()).collect(),
                pos_id: m.part_of_speech_id(),
                dictionary_form: m.dictionary_form().to_string(),
                normalized_form: m.normalized_form().to_string(),
                reading_form: m.reading_form().to_string(),
                is_oov: m.is_oov(),
                dictionary_id: m.dictionary_id(),
                word_id_raw: wid.as_raw(),
                is_system: wid.is_system(),
                is_user: wid.is_user(),
                begin: m.begin(),
                end: m.end(),
                begin_c: m.begin_c(),
                end_c: m.end_c(),
                synonym_group_ids: m.synonym_group_ids().to_vec(),
                total_cost: m.total_cost(),
                dict: self.dict.clone(),
                debug: self.debug.get(),
            };
            ary.push(rb_m)?;
        }
        Ok(ary)
    }

    fn mode(&self) -> String {
        self.mode.to_string()
    }

    fn set_debug(&self, value: bool) {
        self.debug.set(value);
    }

    fn is_debug(&self) -> bool {
        self.debug.get()
    }

    fn internal_cost(&self) -> i32 {
        self.last_internal_cost.get()
    }

    fn tokenize_sentences(&self, text: String) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let splitter = SentenceSplitter::new();
        let result = ruby.ary_new();

        for (_range, sentence) in splitter.split(&text) {
            let morphemes = self.tokenize(sentence.to_string())?;
            result.push(morphemes)?;
        }

        Ok(result)
    }
}

// ---------- StatefulTokenizer ----------

#[magnus::wrap(class = "Kabosu::StatefulTokenizer")]
struct RbStatefulTokenizer {
    dict: Arc<JapaneseDictionary>,
    inner: RefCell<StatefulTokenizer<Arc<JapaneseDictionary>>>,
    mode: Mode,
    debug: Cell<bool>,
    last_internal_cost: Cell<i32>,
}

impl RbStatefulTokenizer {
    fn tokenize(&self, text: String) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();

        let mut tokenizer = self.inner.borrow_mut();
        tokenizer.set_debug(self.debug.get());

        // Reset and write input text
        tokenizer.reset().push_str(&text);

        // Perform tokenization
        tokenizer.do_tokenize().map_err(sudachi_error)?;

        // Collect results into a MorphemeList
        let mut mlist = MorphemeList::empty(self.dict.clone());
        mlist.collect_results(&mut *tokenizer).map_err(sudachi_error)?;

        self.last_internal_cost.set(mlist.get_internal_cost());

        let ary = ruby.ary_new_capa(mlist.len());
        for i in 0..mlist.len() {
            let m = mlist.get(i);
            let wid = m.word_id();
            let rb_m = RbMorpheme {
                surface: m.surface().to_string(),
                pos: m.part_of_speech().iter().map(|s| s.to_string()).collect(),
                pos_id: m.part_of_speech_id(),
                dictionary_form: m.dictionary_form().to_string(),
                normalized_form: m.normalized_form().to_string(),
                reading_form: m.reading_form().to_string(),
                is_oov: m.is_oov(),
                dictionary_id: m.dictionary_id(),
                word_id_raw: wid.as_raw(),
                is_system: wid.is_system(),
                is_user: wid.is_user(),
                begin: m.begin(),
                end: m.end(),
                begin_c: m.begin_c(),
                end_c: m.end_c(),
                synonym_group_ids: m.synonym_group_ids().to_vec(),
                total_cost: m.total_cost(),
                dict: self.dict.clone(),
                debug: self.debug.get(),
            };
            ary.push(rb_m)?;
        }
        Ok(ary)
    }

    fn mode(&self) -> String {
        self.mode.to_string()
    }

    fn set_debug(&self, value: bool) {
        self.debug.set(value);
    }

    fn is_debug(&self) -> bool {
        self.debug.get()
    }

    fn internal_cost(&self) -> i32 {
        self.last_internal_cost.get()
    }

    fn tokenize_sentences(&self, text: String) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let splitter = SentenceSplitter::new();
        let result = ruby.ary_new();

        for (_range, sentence) in splitter.split(&text) {
            let morphemes = self.tokenize(sentence.to_string())?;
            result.push(morphemes)?;
        }

        Ok(result)
    }
}

// ---------- Morpheme ----------

#[magnus::wrap(class = "Kabosu::Morpheme")]
struct RbMorpheme {
    surface: String,
    pos: Vec<String>,
    pos_id: u16,
    dictionary_form: String,
    normalized_form: String,
    reading_form: String,
    is_oov: bool,
    dictionary_id: i32,
    word_id_raw: u32,
    is_system: bool,
    is_user: bool,
    begin: usize,
    end: usize,
    begin_c: usize,
    end_c: usize,
    synonym_group_ids: Vec<u32>,
    total_cost: i32,
    dict: Arc<JapaneseDictionary>,
    debug: bool,
}

impl RbMorpheme {
    fn surface(&self) -> &str {
        &self.surface
    }

    fn part_of_speech(&self) -> Vec<String> {
        self.pos.clone()
    }

    fn part_of_speech_id(&self) -> u16 {
        self.pos_id
    }

    fn dictionary_form(&self) -> &str {
        &self.dictionary_form
    }

    fn normalized_form(&self) -> &str {
        &self.normalized_form
    }

    fn reading_form(&self) -> &str {
        &self.reading_form
    }

    fn is_oov(&self) -> bool {
        self.is_oov
    }

    fn dictionary_id(&self) -> i32 {
        self.dictionary_id
    }

    fn word_id(&self) -> u32 {
        self.word_id_raw
    }

    fn begin(&self) -> usize {
        self.begin
    }

    fn end(&self) -> usize {
        self.end
    }

    fn begin_c(&self) -> usize {
        self.begin_c
    }

    fn end_c(&self) -> usize {
        self.end_c
    }

    fn synonym_group_ids(&self) -> RArray {
        let ruby = Ruby::get().unwrap();
        let ary = ruby.ary_new_capa(self.synonym_group_ids.len());
        for &id in &self.synonym_group_ids {
            let _ = ary.push(id);
        }
        ary
    }

    fn total_cost(&self) -> i32 {
        self.total_cost
    }

    fn is_system(&self) -> bool {
        self.is_system
    }

    fn is_user(&self) -> bool {
        self.is_user
    }

    fn split(&self, mode_str: Option<String>) -> Result<RArray, Error> {
        let target_mode = parse_mode(mode_str.as_deref());
        let ruby = Ruby::get().unwrap();

        // Re-tokenize the surface text with the target mode
        let tokenizer = StatelessTokenizer::new(&*self.dict);
        let morphemes = tokenizer
            .tokenize(&self.surface, target_mode, self.debug)
            .map_err(sudachi_error)?;

        let ary = ruby.ary_new_capa(morphemes.len());
        for i in 0..morphemes.len() {
            let m = morphemes.get(i);
            let wid = m.word_id();
            let rb_m = RbMorpheme {
                surface: m.surface().to_string(),
                pos: m.part_of_speech().iter().map(|s| s.to_string()).collect(),
                pos_id: m.part_of_speech_id(),
                dictionary_form: m.dictionary_form().to_string(),
                normalized_form: m.normalized_form().to_string(),
                reading_form: m.reading_form().to_string(),
                is_oov: m.is_oov(),
                dictionary_id: m.dictionary_id(),
                word_id_raw: wid.as_raw(),
                is_system: wid.is_system(),
                is_user: wid.is_user(),
                begin: m.begin(),
                end: m.end(),
                begin_c: m.begin_c(),
                end_c: m.end_c(),
                synonym_group_ids: m.synonym_group_ids().to_vec(),
                total_cost: m.total_cost(),
                dict: self.dict.clone(),
                debug: self.debug,
            };
            ary.push(rb_m)?;
        }
        Ok(ary)
    }

    fn inspect(&self) -> String {
        format!(
            "#<Kabosu::Morpheme surface=\"{}\" pos=[{}] reading=\"{}\" {}..{}>",
            self.surface,
            self.pos.join(", "),
            self.reading_form,
            self.begin_c,
            self.end_c,
        )
    }

    fn to_s(&self) -> &str {
        &self.surface
    }
}

// ---------- Helpers ----------

fn parse_mode(mode: Option<&str>) -> Mode {
    match mode {
        Some("A") | Some("a") => Mode::A,
        Some("B") | Some("b") => Mode::B,
        _ => Mode::C,
    }
}

// ---------- Init ----------

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("Kabosu")?;

    // Kabosu::Dictionary
    let dict_class = module.define_class("Dictionary", ruby.class_object())?;
    dict_class.define_singleton_method("new", function!(RbDictionary::new, -1))?;
    dict_class.define_method("create", method!(RbDictionary::create, 1))?;
    dict_class.define_method("create_stateful", method!(RbDictionary::create_stateful, 1))?;

    // Kabosu::Tokenizer
    let tok_class = module.define_class("Tokenizer", ruby.class_object())?;
    tok_class.define_method("tokenize", method!(RbTokenizer::tokenize, 1))?;
    tok_class.define_method("mode", method!(RbTokenizer::mode, 0))?;
    tok_class.define_method("debug=", method!(RbTokenizer::set_debug, 1))?;
    tok_class.define_method("debug?", method!(RbTokenizer::is_debug, 0))?;
    tok_class.define_method("internal_cost", method!(RbTokenizer::internal_cost, 0))?;
    tok_class.define_method(
        "tokenize_sentences",
        method!(RbTokenizer::tokenize_sentences, 1),
    )?;

    // Kabosu::StatefulTokenizer
    let stok_class = module.define_class("StatefulTokenizer", ruby.class_object())?;
    stok_class.define_method("tokenize", method!(RbStatefulTokenizer::tokenize, 1))?;
    stok_class.define_method("mode", method!(RbStatefulTokenizer::mode, 0))?;
    stok_class.define_method("debug=", method!(RbStatefulTokenizer::set_debug, 1))?;
    stok_class.define_method("debug?", method!(RbStatefulTokenizer::is_debug, 0))?;
    stok_class.define_method("internal_cost", method!(RbStatefulTokenizer::internal_cost, 0))?;
    stok_class.define_method(
        "tokenize_sentences",
        method!(RbStatefulTokenizer::tokenize_sentences, 1),
    )?;

    // Kabosu::Morpheme
    let morph_class = module.define_class("Morpheme", ruby.class_object())?;
    morph_class.define_method("surface", method!(RbMorpheme::surface, 0))?;
    morph_class.define_method("part_of_speech", method!(RbMorpheme::part_of_speech, 0))?;
    morph_class.define_method("part_of_speech_id", method!(RbMorpheme::part_of_speech_id, 0))?;
    morph_class.define_method("dictionary_form", method!(RbMorpheme::dictionary_form, 0))?;
    morph_class.define_method("normalized_form", method!(RbMorpheme::normalized_form, 0))?;
    morph_class.define_method("reading_form", method!(RbMorpheme::reading_form, 0))?;
    morph_class.define_method("oov?", method!(RbMorpheme::is_oov, 0))?;
    morph_class.define_method("dictionary_id", method!(RbMorpheme::dictionary_id, 0))?;
    morph_class.define_method("word_id", method!(RbMorpheme::word_id, 0))?;
    morph_class.define_method("begin", method!(RbMorpheme::begin, 0))?;
    morph_class.define_method("end", method!(RbMorpheme::end, 0))?;
    morph_class.define_method("begin_c", method!(RbMorpheme::begin_c, 0))?;
    morph_class.define_method("end_c", method!(RbMorpheme::end_c, 0))?;
    morph_class.define_method("synonym_group_ids", method!(RbMorpheme::synonym_group_ids, 0))?;
    morph_class.define_method("total_cost", method!(RbMorpheme::total_cost, 0))?;
    morph_class.define_method("system?", method!(RbMorpheme::is_system, 0))?;
    morph_class.define_method("user?", method!(RbMorpheme::is_user, 0))?;
    morph_class.define_method("split", method!(RbMorpheme::split, 1))?;
    morph_class.define_method("inspect", method!(RbMorpheme::inspect, 0))?;
    morph_class.define_method("to_s", method!(RbMorpheme::to_s, 0))?;

    // Kabosu::MODE_A, MODE_B, MODE_C constants
    module.const_set("MODE_A", ruby.str_new("A"))?;
    module.const_set("MODE_B", ruby.str_new("B"))?;
    module.const_set("MODE_C", ruby.str_new("C"))?;

    Ok(())
}
