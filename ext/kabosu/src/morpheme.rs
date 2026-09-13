use magnus::typed_data::Obj;
use magnus::value::{Opaque, ReprValue};
use magnus::{gc, DataTypeFunctions, Error, RArray, RString, Ruby, TypedData, Value};
use std::cell::OnceCell;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use sudachi::analysis::morpheme::{Morpheme as SudachiMorpheme, SingleMorpheme};
use sudachi::analysis::Mode;
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::dic::subset::InfoSubset;
use sudachi::dic::word_id::WordId;
use sudachi::dic::DictionaryAccess;
use sudachi::text_normalizer::TextNormalizer;

use crate::errors::sudachi_error;
use crate::parsing::parse_mode;

#[derive(Clone)]
pub(crate) struct MorphemeData {
    pub(crate) surface: String,
    pub(crate) dictionary_form: String,
    pub(crate) normalized_form: String,
    pub(crate) reading_form: String,
    pub(crate) pos_id: u16,
    pub(crate) word_id_raw: u32,
    pub(crate) is_oov: bool,
    pub(crate) dictionary_id: i32,
    pub(crate) is_system: bool,
    pub(crate) is_user: bool,
    pub(crate) begin: usize,
    pub(crate) end: usize,
    pub(crate) begin_c: usize,
    pub(crate) end_c: usize,
    pub(crate) total_cost: i32,
    // Bytes of the normalized index form (upstream's index_form_length). Known
    // for every node, OOV and joined ones included, so it is not a lazy field.
    pub(crate) head_word_length: usize,
}

pub(crate) fn build_morpheme_data<T>(m: &SudachiMorpheme<'_, T>) -> MorphemeData
where
    T: DictionaryAccess,
{
    let surface = {
        let s = m.surface();
        s.to_string()
    };

    MorphemeData {
        surface,
        dictionary_form: m.dictionary_form().to_string(),
        normalized_form: m.normalized_form().to_string(),
        reading_form: m.reading_form().to_string(),
        pos_id: m.part_of_speech_id(),
        word_id_raw: m.word_id().as_raw(),
        is_oov: m.is_oov(),
        dictionary_id: m.dictionary_id(),
        is_system: m.word_id().is_system(),
        is_user: m.word_id().is_user(),
        begin: m.begin(),
        end: m.end(),
        begin_c: m.begin_c(),
        end_c: m.end_c(),
        total_cost: m.total_cost(),
        head_word_length: m.get_word_info().index_form_length(),
    }
}

/// A morpheme that stands on its own rather than inside a tokenized sentence:
/// a dictionary entry or a hand-made OOV word. Offsets cover its own surface
/// (the headword, for entries) and there is no path cost.
pub(crate) fn data_from_single<D>(m: &SingleMorpheme<D>) -> MorphemeData
where
    D: DictionaryAccess + Clone,
{
    let wid = m.word_id();
    MorphemeData {
        surface: m.surface().to_string(),
        dictionary_form: m.dictionary_form().to_string(),
        normalized_form: m.normalized_form().to_string(),
        reading_form: m.reading_form().to_string(),
        pos_id: m.part_of_speech_id(),
        word_id_raw: wid.as_raw(),
        is_oov: m.is_oov(),
        dictionary_id: dictionary_id_of(wid),
        is_system: wid.is_system(),
        is_user: wid.is_user(),
        begin: m.begin(),
        end: m.end(),
        begin_c: m.begin_c(),
        end_c: m.end_c(),
        total_cost: 0,
        head_word_length: m.get_word_info().index_form_length(),
    }
}

#[derive(Clone, Copy)]
struct CachedRArray(RArray);
unsafe impl Send for CachedRArray {}

static POS_CACHE: OnceLock<Mutex<HashMap<(usize, u16), CachedRArray>>> = OnceLock::new();

pub(crate) fn rb_morpheme_from_data(
    data: MorphemeData,
    dict: Arc<JapaneseDictionary>,
    debug: bool,
) -> RbMorpheme {
    RbMorpheme {
        data,
        dict,
        debug,
        word_fields: OnceCell::new(),
        surface_cache: OnceCell::new(),
        dictionary_form_cache: OnceCell::new(),
        pos_cache: OnceCell::new(),
    }
}

// One frozen Ruby String per slot, built on first ask.
//
// FROZEN ON PURPOSE, and not only for safety: `+str` returns self for a mutable
// String and a mutable COPY for a frozen one, so a shared mutable value would let
// an innocent `buf = +m.surface; buf << other` write straight through into the
// cache and corrupt every later read. Frozen, that idiom keeps working unchanged
// and anything else fails loudly instead of silently.
fn frozen_string(ruby: &Ruby, cell: &OnceCell<Opaque<RString>>, source: &str) -> RString {
    let cached = cell.get_or_init(|| {
        let rstr = ruby.str_new(source);
        rstr.as_value().freeze();
        Opaque::from(rstr)
    });
    ruby.get_inner(*cached)
}

// sudachi.rs 0.7 made `WordId::from_raw` crate-private; `new` rebuilds the same
// value from its 4-bit dictionary and 28-bit entry halves.
pub(crate) fn word_id_from_raw(raw: u32) -> WordId {
    WordId::new((raw >> 28) as u8, raw & 0x0fff_ffff)
}

pub(crate) fn dictionary_id_of(wid: WordId) -> i32 {
    if wid.is_oov() {
        -1
    } else {
        wid.dict().as_raw() as i32
    }
}

/// Character boundaries of `text` plus the byte length that each character
/// prefix normalizes to under the dictionary's input-text plugins. Dictionary
/// lengths (index_form_length, lookup ends) count normalized bytes, so this is
/// what maps them back onto the original text.
pub(crate) struct PrefixMap {
    pub(crate) byte_boundaries: Vec<usize>,
    normalized_lens: Vec<usize>,
}

impl PrefixMap {
    pub(crate) fn new(dict: &Arc<JapaneseDictionary>, text: &str) -> Result<Self, Error> {
        let mut byte_boundaries: Vec<usize> = text.char_indices().map(|(i, _)| i).collect();
        byte_boundaries.push(text.len());

        let mut normalizer = TextNormalizer::from_shared_dictionary(dict.clone());
        let mut normalized_lens = Vec::with_capacity(byte_boundaries.len());
        normalized_lens.push(0);
        for &end in &byte_boundaries[1..] {
            let normalized = normalizer.normalize(&text[..end]).map_err(sudachi_error)?;
            normalized_lens.push(normalized.len());
        }

        Ok(Self {
            byte_boundaries,
            normalized_lens,
        })
    }

    pub(crate) fn char_len(&self) -> usize {
        self.byte_boundaries.len() - 1
    }

    /// The LAST character boundary at or after `from` whose prefix normalizes
    /// to at most `target` bytes. Last, because characters the plugins fold away
    /// (a run of 〜, a closed yomigana bracket) belong to the word before them.
    pub(crate) fn char_end(&self, from: usize, target: usize) -> usize {
        (from..self.normalized_lens.len())
            .rev()
            .find(|&k| self.normalized_lens[k] <= target)
            .unwrap_or(from)
    }
}

fn ids_to_array<T: magnus::IntoValue + Copy>(ids: &[T]) -> Result<RArray, Error> {
    let ruby = Ruby::get().unwrap();
    let ary = ruby.ary_new_capa(ids.len());
    for &id in ids {
        ary.push(id)?;
    }
    Ok(ary)
}

#[derive(TypedData)]
#[magnus(class = "Kabosu::Morpheme", mark)]
pub(crate) struct RbMorpheme {
    data: MorphemeData,
    dict: Arc<JapaneseDictionary>,
    debug: bool,
    word_fields: OnceCell<LazyWordFields>,
    // Ruby objects handed to the same caller over and over: built once per
    // morpheme rather than once per call. See `surface` for the reasoning and
    // for why they are frozen.
    surface_cache: OnceCell<Opaque<RString>>,
    dictionary_form_cache: OnceCell<Opaque<RString>>,
    pos_cache: OnceCell<Opaque<RArray>>,
}

impl DataTypeFunctions for RbMorpheme {
    // The cached surface is reachable only from Rust, so the GC cannot see it
    // without being told. Missing this would let a live String be collected.
    fn mark(&self, marker: &gc::Marker) {
        if let Some(cached) = self.surface_cache.get() {
            marker.mark(*cached);
        }
        if let Some(cached) = self.dictionary_form_cache.get() {
            marker.mark(*cached);
        }
        if let Some(cached) = self.pos_cache.get() {
            marker.mark(*cached);
        }
    }
}

struct LazyWordFields {
    synonym_group_ids: Vec<i32>,
    dictionary_form_word_id: i64,
    a_unit_split: Vec<u32>,
    b_unit_split: Vec<u32>,
    c_unit_split: Vec<u32>,
    word_structure: Vec<u32>,
    user_data: String,
}

impl RbMorpheme {
    fn fallback_word_fields(&self) -> LazyWordFields {
        LazyWordFields {
            synonym_group_ids: Vec::new(),
            dictionary_form_word_id: -1,
            a_unit_split: Vec::new(),
            b_unit_split: Vec::new(),
            c_unit_split: Vec::new(),
            word_structure: Vec::new(),
            user_data: String::new(),
        }
    }

    fn resolve_word_fields(&self) -> &LazyWordFields {
        self.word_fields.get_or_init(|| {
            if self.data.is_oov || self.data.dictionary_id < 0 {
                return self.fallback_word_fields();
            }

            let wid = word_id_from_raw(self.data.word_id_raw);

            let info_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                self.dict.lexicon().get_word_info(wid)
            }));

            match info_result {
                Ok(Ok(info)) => LazyWordFields {
                    synonym_group_ids: info.synonym_group_ids().to_vec(),
                    // V1 dictionaries point a word that is its own dictionary
                    // form at itself; v0.6 stored -1 there, which callers rely on.
                    dictionary_form_word_id: match info.borrow_data().dictionary_form_word_id() {
                        d if d == wid => -1,
                        d => i64::from(d.as_raw()),
                    },
                    a_unit_split: info.a_unit_split().iter().map(WordId::as_raw).collect(),
                    b_unit_split: info.b_unit_split().iter().map(WordId::as_raw).collect(),
                    c_unit_split: info.c_unit_split().iter().map(WordId::as_raw).collect(),
                    word_structure: info.word_structure().iter().map(WordId::as_raw).collect(),
                    user_data: info.user_data().to_string(),
                },
                _ => self.fallback_word_fields(),
            }
        })
    }

    fn split_ids_from_lexicon(&self, mode: Mode) -> Result<Vec<u32>, Error> {
        if self.data.is_oov || self.data.dictionary_id < 0 {
            return Ok(Vec::new());
        }
        let wid = word_id_from_raw(self.data.word_id_raw);

        let info_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.dict.lexicon().get_word_info(wid)
        }));
        let info = match info_result {
            Ok(Ok(info)) => info,
            Ok(Err(e)) => return Err(sudachi_error(e)),
            Err(_) => return Err(sudachi_error("panic while reading word info for split")),
        };
        let ids = match mode {
            Mode::A => info.a_unit_split(),
            Mode::B => info.b_unit_split(),
            Mode::C => &[],
        };
        Ok(ids.iter().map(WordId::as_raw).collect())
    }

    fn split_ids_for_mode(&self, mode: Mode) -> Result<Vec<u32>, Error> {
        match mode {
            Mode::A => {
                let ids = &self.resolve_word_fields().a_unit_split;
                if ids.is_empty() {
                    self.split_ids_from_lexicon(mode)
                } else {
                    Ok(ids.clone())
                }
            }
            Mode::B => {
                let ids = &self.resolve_word_fields().b_unit_split;
                if ids.is_empty() {
                    self.split_ids_from_lexicon(mode)
                } else {
                    Ok(ids.clone())
                }
            }
            Mode::C => Ok(Vec::new()),
        }
    }

    // Mirrors upstream's node splitting: each child spans its index_form_length
    // in NORMALIZED bytes, mapped back onto the original surface. Sizing by the
    // child's own text instead misplaces every cut where normalization changes
    // the text (half-width kana, 〜 runs, yomigana).
    fn build_split_children(&self, split_ids: &[u32]) -> Result<Vec<MorphemeData>, Error> {
        let surface = &self.data.surface;
        let prefixes = PrefixMap::new(&self.dict, surface)?;
        let char_len = prefixes.char_len();
        let lexicon = self.dict.lexicon();

        let mut char_pos = 0usize;
        let mut normalized_end = 0usize;
        let mut result = Vec::with_capacity(split_ids.len());

        for (i, &raw_wid) in split_ids.iter().enumerate() {
            let wid = word_id_from_raw(raw_wid);
            let info_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                lexicon.get_word_info(wid)
            }));
            let info = match info_result {
                Ok(Ok(info)) => info,
                Ok(Err(e)) => return Err(sudachi_error(e)),
                Err(_) => {
                    return Err(sudachi_error(
                        "panic while reading child word info for split",
                    ))
                }
            };

            normalized_end += info.index_form_length();
            // The last child takes whatever is left, so the children always
            // cover the parent surface exactly.
            let end_char = if i + 1 == split_ids.len() {
                char_len
            } else {
                prefixes.char_end(char_pos, normalized_end)
            };

            let start_char = char_pos;
            let start_byte = prefixes.byte_boundaries[start_char];
            let end_byte = prefixes.byte_boundaries[end_char];
            char_pos = end_char;

            let child = MorphemeData {
                surface: surface[start_byte..end_byte].to_string(),
                dictionary_form: info.dictionary_form(lexicon).to_string(),
                normalized_form: info.normalized_form(lexicon).to_string(),
                reading_form: info.reading_form(lexicon).to_string(),
                pos_id: info.pos_id(),
                word_id_raw: raw_wid,
                is_oov: wid.is_oov(),
                dictionary_id: dictionary_id_of(wid),
                is_system: wid.is_system(),
                is_user: wid.is_user(),
                begin: self.data.begin + start_byte,
                end: self.data.begin + end_byte,
                begin_c: self.data.begin_c + start_char,
                end_c: self.data.begin_c + end_char,
                total_cost: self.data.total_cost,
                head_word_length: info.index_form_length(),
            };
            result.push(child);
        }

        Ok(result)
    }

    // One frozen Ruby String per morpheme, not one per call.
    //
    // Callers ask this a lot: measured on a real tokenizer workload, 58,874 calls
    // across 3,569 distinct morphemes, 16.5 each, so 94% of the Strings this used
    // to allocate were identical copies of one already made. Returning `&str` let
    // magnus build a fresh RString every time.
    //
    // FROZEN ON PURPOSE, and not only for safety: `+str` returns self for a
    // mutable String and a mutable COPY for a frozen one, so a shared mutable
    // surface would let an innocent `buf = +m.surface; buf << other` write through
    // into the cache and corrupt every later read. Frozen, that idiom keeps
    // working unchanged and anything else fails loudly. `part_of_speech` freezes
    // what it caches for the same reason.
    // Takes `&Ruby` as its first parameter rather than calling `Ruby::get()`.
    // magnus hands that handle over for free (`Ruby::get_with` is
    // `Self(PhantomData)`, zero instructions), where `Ruby::get()` costs a
    // thread-local access, a RefCell borrow and a Result construction on EVERY
    // call — including the cache-hit path, whose only use for the handle is
    // `get_inner`, which discards it. With the allocations gone that round trip
    // was a real share of what these accessors still cost. `method!(.., 0)` in
    // lib.rs is unchanged: magnus resolves the &Ruby form on the fn pointer.
    pub(crate) fn surface(ruby: &Ruby, rb_self: &Self) -> RString {
        frozen_string(ruby, &rb_self.surface_cache, &rb_self.data.surface)
    }

    // Asked more than any other method on this class: 35.7 times per morpheme on
    // a real workload. The process-wide POS_CACHE below already makes the ANSWER
    // free of allocation, but every one of those calls still took a global Mutex
    // and hashed a key to reach it. A morpheme's part of speech cannot change, so
    // the first ask is remembered here and the rest never reach the lock.
    pub(crate) fn part_of_speech(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        if let Some(cached) = rb_self.pos_cache.get() {
            return Ok(ruby.get_inner(*cached));
        }

        let ary = rb_self.pos_from_shared_cache()?;
        let _ = rb_self.pos_cache.set(Opaque::from(ary));
        Ok(ary)
    }

    fn pos_from_shared_cache(&self) -> Result<RArray, Error> {
        let dict_ptr = Arc::as_ptr(&self.dict) as usize;
        let pos_id = self.data.pos_id;

        {
            let cache = POS_CACHE
                .get_or_init(|| Mutex::new(HashMap::new()))
                .lock()
                .unwrap();
            if let Some(&cached) = cache.get(&(dict_ptr, pos_id)) {
                return Ok(cached.0);
            }
        }

        let ruby = Ruby::get().unwrap();
        let ary = ruby.ary_new();
        for s in self.dict.grammar().pos_components(pos_id) {
            let rstr: RString = ruby.str_new(s);
            rstr.as_value().freeze();
            ary.push(rstr)?;
        }
        ary.as_value().freeze();
        // Pin permanently: POS combinations are bounded (~hundreds) and frozen
        // arrays are tiny. The cache lives for the process lifetime.
        gc::register_mark_object(ary);

        POS_CACHE
            .get_or_init(|| Mutex::new(HashMap::new()))
            .lock()
            .unwrap()
            .insert((dict_ptr, pos_id), CachedRArray(ary));

        Ok(ary)
    }

    pub(crate) fn part_of_speech_id(&self) -> u16 {
        self.data.pos_id
    }

    // Cached like `surface`, and for the same measured reason: 6.0 calls per
    // morpheme on a real workload, so five of every six Strings this built were
    // a copy of one it had already built.
    pub(crate) fn dictionary_form(ruby: &Ruby, rb_self: &Self) -> RString {
        frozen_string(
            ruby,
            &rb_self.dictionary_form_cache,
            &rb_self.data.dictionary_form,
        )
    }

    pub(crate) fn normalized_form(&self) -> &str {
        &self.data.normalized_form
    }

    pub(crate) fn reading_form(&self) -> &str {
        &self.data.reading_form
    }

    pub(crate) fn is_oov(&self) -> bool {
        self.data.is_oov
    }

    pub(crate) fn dictionary_id(&self) -> i32 {
        self.data.dictionary_id
    }

    pub(crate) fn word_id(&self) -> u32 {
        self.data.word_id_raw
    }

    pub(crate) fn dictionary_form_word_id(&self) -> i64 {
        self.resolve_word_fields().dictionary_form_word_id
    }

    pub(crate) fn head_word_length(&self) -> usize {
        self.data.head_word_length
    }

    pub(crate) fn begin(&self) -> usize {
        self.data.begin
    }

    pub(crate) fn end(&self) -> usize {
        self.data.end
    }

    pub(crate) fn begin_c(&self) -> usize {
        self.data.begin_c
    }

    pub(crate) fn end_c(&self) -> usize {
        self.data.end_c
    }

    pub(crate) fn synonym_group_ids(&self) -> Result<RArray, Error> {
        ids_to_array(&self.resolve_word_fields().synonym_group_ids)
    }

    pub(crate) fn a_unit_split(&self) -> Result<RArray, Error> {
        ids_to_array(&self.resolve_word_fields().a_unit_split)
    }

    pub(crate) fn b_unit_split(&self) -> Result<RArray, Error> {
        ids_to_array(&self.resolve_word_fields().b_unit_split)
    }

    pub(crate) fn c_unit_split(&self) -> Result<RArray, Error> {
        ids_to_array(&self.resolve_word_fields().c_unit_split)
    }

    pub(crate) fn user_data(&self) -> &str {
        &self.resolve_word_fields().user_data
    }

    pub(crate) fn dictionary_form_morpheme(
        ruby: &Ruby,
        rb_self: Obj<Self>,
    ) -> Result<Value, Error> {
        Self::form_morpheme(ruby, rb_self, InfoSubset::DICTIONARY_FORM)
    }

    pub(crate) fn normalized_form_morpheme(
        ruby: &Ruby,
        rb_self: Obj<Self>,
    ) -> Result<Value, Error> {
        Self::form_morpheme(ruby, rb_self, InfoSubset::NORMALIZED_FORM)
    }

    // The dictionary entry this morpheme's dictionary/normalized form refers to,
    // as a standalone morpheme. A word that is its own form (and any OOV word)
    // answers with itself, the same object, as upstream does.
    fn form_morpheme(ruby: &Ruby, rb_self: Obj<Self>, form: InfoSubset) -> Result<Value, Error> {
        if rb_self.data.is_oov {
            return Ok(rb_self.as_value());
        }

        let wid = word_id_from_raw(rb_self.data.word_id_raw);
        let lexicon = rb_self.dict.lexicon();
        let info = lexicon
            .get_word_info_subset(wid, form)
            .map_err(sudachi_error)?;
        let data = info.borrow_data();
        let form_wid = if form == InfoSubset::DICTIONARY_FORM {
            data.dictionary_form_word_id()
        } else {
            data.normalized_form_word_id()
        };

        if form_wid == WordId::INVALID
            || form_wid == wid
            || form_wid.is_oov()
            || form_wid.is_special()
        {
            return Ok(rb_self.as_value());
        }

        let single = SingleMorpheme::from_word_id(&*rb_self.dict, form_wid, InfoSubset::all())
            .map_err(sudachi_error)?;
        let morpheme = rb_morpheme_from_data(
            data_from_single(&single),
            rb_self.dict.clone(),
            rb_self.debug,
        );
        Ok(ruby.obj_wrap(morpheme).as_value())
    }

    pub(crate) fn word_structure(&self) -> Result<RArray, Error> {
        ids_to_array(&self.resolve_word_fields().word_structure)
    }

    pub(crate) fn total_cost(&self) -> i32 {
        self.data.total_cost
    }

    pub(crate) fn is_system(&self) -> bool {
        self.data.is_system
    }

    pub(crate) fn is_user(&self) -> bool {
        self.data.is_user
    }

    pub(crate) fn split(
        &self,
        mode_str: Option<String>,
        out: Option<RArray>,
        add_single: Option<bool>,
    ) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let add_single = add_single.unwrap_or(true);

        let target_mode = parse_mode(mode_str.as_deref())?;
        let split_ids = self.split_ids_for_mode(target_mode)?;
        let children = if split_ids.is_empty() {
            Vec::new()
        } else {
            self.build_split_children(&split_ids)?
        };

        let ary = match out {
            Some(ary) => {
                ary.clear()?;
                ary
            }
            None => ruby.ary_new_capa(if children.is_empty() {
                1
            } else {
                children.len()
            }),
        };

        if children.is_empty() {
            if add_single {
                ary.push(rb_morpheme_from_data(
                    self.data.clone(),
                    self.dict.clone(),
                    self.debug,
                ))?;
            }
        } else {
            for child in children {
                ary.push(rb_morpheme_from_data(child, self.dict.clone(), self.debug))?;
            }
        }

        Ok(ary)
    }

    pub(crate) fn inspect(&self) -> String {
        format!(
            "#<Kabosu::Morpheme surface=\"{}\" pos_id={} reading=\"{}\" {}..{}>",
            self.data.surface,
            self.data.pos_id,
            self.reading_form(),
            self.data.begin_c,
            self.data.end_c,
        )
    }

    pub(crate) fn to_s(&self) -> &str {
        &self.data.surface
    }
}
