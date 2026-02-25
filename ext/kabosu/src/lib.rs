use magnus::{function, method, prelude::*, Error, RArray, Ruby, Value};
use std::sync::Arc;
use sudachi::analysis::stateless_tokenizer::StatelessTokenizer;
use sudachi::analysis::{Mode, Tokenize};
use sudachi::config::Config;
use sudachi::dic::dictionary::JapaneseDictionary;

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
        }
    }
}

// ---------- Tokenizer ----------

#[magnus::wrap(class = "Kabosu::Tokenizer")]
struct RbTokenizer {
    dict: Arc<JapaneseDictionary>,
    mode: Mode,
}

impl RbTokenizer {
    fn tokenize(&self, text: String) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let tokenizer = StatelessTokenizer::new(&*self.dict);
        let morphemes = tokenizer
            .tokenize(&text, self.mode, false)
            .map_err(sudachi_error)?;

        let ary = ruby.ary_new_capa(morphemes.len());
        for i in 0..morphemes.len() {
            let m = morphemes.get(i);
            let rb_m = RbMorpheme {
                surface: m.surface().to_string(),
                pos: m.part_of_speech().iter().map(|s| s.to_string()).collect(),
                pos_id: m.part_of_speech_id(),
                dictionary_form: m.dictionary_form().to_string(),
                normalized_form: m.normalized_form().to_string(),
                reading_form: m.reading_form().to_string(),
                is_oov: m.is_oov(),
                dictionary_id: m.dictionary_id(),
                word_id: m.word_id().as_raw(),
                begin: m.begin(),
                end: m.end(),
            };
            ary.push(rb_m)?;
        }
        Ok(ary)
    }

    fn mode(&self) -> String {
        self.mode.to_string()
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
    word_id: u32,
    begin: usize,
    end: usize,
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
        self.word_id
    }

    fn begin(&self) -> usize {
        self.begin
    }

    fn end(&self) -> usize {
        self.end
    }

    fn inspect(&self) -> String {
        format!(
            "#<Kabosu::Morpheme surface=\"{}\" pos=[{}] reading=\"{}\">",
            self.surface,
            self.pos.join(", "),
            self.reading_form,
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

    // Kabosu::Tokenizer
    let tok_class = module.define_class("Tokenizer", ruby.class_object())?;
    tok_class.define_method("tokenize", method!(RbTokenizer::tokenize, 1))?;
    tok_class.define_method("mode", method!(RbTokenizer::mode, 0))?;

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
    morph_class.define_method("inspect", method!(RbMorpheme::inspect, 0))?;
    morph_class.define_method("to_s", method!(RbMorpheme::to_s, 0))?;

    // Kabosu::MODE_A, MODE_B, MODE_C constants
    module.const_set("MODE_A", ruby.str_new("A"))?;
    module.const_set("MODE_B", ruby.str_new("B"))?;
    module.const_set("MODE_C", ruby.str_new("C"))?;

    Ok(())
}
