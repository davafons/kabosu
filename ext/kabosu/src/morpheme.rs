use magnus::{Error, RArray, Ruby};
use std::cell::OnceCell;
use std::sync::Arc;
use sudachi::analysis::morpheme::Morpheme as SudachiMorpheme;
use sudachi::analysis::stateless_tokenizer::DictionaryAccess;
use sudachi::analysis::Mode;
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::dic::word_id::WordId;

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
    }
}

pub(crate) fn rb_morpheme_from_data(
    data: MorphemeData,
    dict: Arc<JapaneseDictionary>,
    debug: bool,
) -> RbMorpheme {
    RbMorpheme {
        data,
        dict,
        debug,
        pos: OnceCell::new(),
        word_fields: OnceCell::new(),
    }
}

fn vec_u32_to_array(ids: &[u32]) -> Result<RArray, Error> {
    let ruby = Ruby::get().unwrap();
    let ary = ruby.ary_new_capa(ids.len());
    for &id in ids {
        ary.push(id)?;
    }
    Ok(ary)
}

#[magnus::wrap(class = "Kabosu::Morpheme")]
pub(crate) struct RbMorpheme {
    data: MorphemeData,
    dict: Arc<JapaneseDictionary>,
    debug: bool,
    pos: OnceCell<Vec<String>>,
    word_fields: OnceCell<LazyWordFields>,
}

struct LazyWordFields {
    synonym_group_ids: Vec<u32>,
    dictionary_form_word_id: i32,
    head_word_length: usize,
    a_unit_split: Vec<u32>,
    b_unit_split: Vec<u32>,
    word_structure: Vec<u32>,
}

impl RbMorpheme {
    fn fallback_word_fields(&self) -> LazyWordFields {
        LazyWordFields {
            synonym_group_ids: Vec::new(),
            dictionary_form_word_id: -1,
            head_word_length: self.data.surface.chars().count(),
            a_unit_split: Vec::new(),
            b_unit_split: Vec::new(),
            word_structure: Vec::new(),
        }
    }

    fn resolve_word_fields(&self) -> &LazyWordFields {
        self.word_fields.get_or_init(|| {
            if self.data.is_oov || self.data.dictionary_id < 0 {
                return self.fallback_word_fields();
            }

            let wid = WordId::from_raw(self.data.word_id_raw);

            let info_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                self.dict.lexicon().get_word_info(wid)
            }));

            match info_result {
                Ok(Ok(info)) => LazyWordFields {
                    synonym_group_ids: info.synonym_group_ids().to_vec(),
                    dictionary_form_word_id: info.dictionary_form_word_id(),
                    head_word_length: info.head_word_length(),
                    a_unit_split: info.a_unit_split().iter().map(WordId::as_raw).collect(),
                    b_unit_split: info.b_unit_split().iter().map(WordId::as_raw).collect(),
                    word_structure: info.word_structure().iter().map(WordId::as_raw).collect(),
                },
                _ => self.fallback_word_fields(),
            }
        })
    }

    fn split_ids_from_lexicon(&self, mode: Mode) -> Result<Vec<u32>, Error> {
        if self.data.is_oov || self.data.dictionary_id < 0 {
            return Ok(Vec::new());
        }
        let wid = WordId::from_raw(self.data.word_id_raw);

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

    fn build_split_children(&self, split_ids: &[u32]) -> Result<Vec<MorphemeData>, Error> {
        let surface = &self.data.surface;
        let mut byte_boundaries: Vec<usize> = surface.char_indices().map(|(i, _)| i).collect();
        byte_boundaries.push(surface.len());
        let char_len = byte_boundaries.len().saturating_sub(1);

        let mut char_pos = 0usize;
        let mut result = Vec::with_capacity(split_ids.len());

        for (i, &raw_wid) in split_ids.iter().enumerate() {
            let wid = WordId::from_raw(raw_wid);
            let info_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                self.dict.lexicon().get_word_info(wid)
            }));
            let info = match info_result {
                Ok(Ok(info)) => info,
                Ok(Err(e)) => return Err(sudachi_error(e)),
                Err(_) => return Err(sudachi_error("panic while reading child word info for split")),
            };

            // head_word_length is in codepoints; clamp to remaining characters.
            let mut span_chars = info.head_word_length();
            if span_chars == 0 || char_pos + span_chars > char_len || i + 1 == split_ids.len() {
                span_chars = char_len.saturating_sub(char_pos);
            }

            let start_char = char_pos;
            let end_char = char_pos + span_chars;
            let start_byte = byte_boundaries[start_char];
            let end_byte = byte_boundaries[end_char];
            char_pos = end_char;

            let child = MorphemeData {
                surface: surface[start_byte..end_byte].to_string(),
                dictionary_form: info.dictionary_form().to_string(),
                normalized_form: info.normalized_form().to_string(),
                reading_form: info.reading_form().to_string(),
                pos_id: info.pos_id(),
                word_id_raw: raw_wid,
                is_oov: wid.is_oov(),
                dictionary_id: if wid.is_oov() { -1 } else { wid.dic() as i32 },
                is_system: wid.is_system(),
                is_user: wid.is_user(),
                begin: self.data.begin + start_byte,
                end: self.data.begin + end_byte,
                begin_c: self.data.begin_c + start_char,
                end_c: self.data.begin_c + end_char,
                total_cost: self.data.total_cost,
            };
            result.push(child);
        }

        Ok(result)
    }

    pub(crate) fn surface(&self) -> &str {
        &self.data.surface
    }

    pub(crate) fn part_of_speech(&self) -> Vec<String> {
        self.pos
            .get_or_init(|| {
                self.dict
                    .grammar()
                    .pos_components(self.data.pos_id)
                    .iter()
                    .map(|s| s.to_string())
                    .collect()
            })
            .clone()
    }

    pub(crate) fn part_of_speech_id(&self) -> u16 {
        self.data.pos_id
    }

    pub(crate) fn dictionary_form(&self) -> &str {
        &self.data.dictionary_form
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

    pub(crate) fn dictionary_form_word_id(&self) -> i32 {
        self.resolve_word_fields().dictionary_form_word_id
    }

    pub(crate) fn head_word_length(&self) -> usize {
        self.resolve_word_fields().head_word_length
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
        vec_u32_to_array(&self.resolve_word_fields().synonym_group_ids)
    }

    pub(crate) fn a_unit_split(&self) -> Result<RArray, Error> {
        vec_u32_to_array(&self.resolve_word_fields().a_unit_split)
    }

    pub(crate) fn b_unit_split(&self) -> Result<RArray, Error> {
        vec_u32_to_array(&self.resolve_word_fields().b_unit_split)
    }

    pub(crate) fn word_structure(&self) -> Result<RArray, Error> {
        vec_u32_to_array(&self.resolve_word_fields().word_structure)
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
            None => ruby.ary_new_capa(if children.is_empty() { 1 } else { children.len() }),
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
