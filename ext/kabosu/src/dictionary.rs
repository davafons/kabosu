use magnus::value::ReprValue;
use magnus::{Error, RArray, Ruby, Value};
use std::path::Path;
use std::sync::Arc;
use sudachi::config::{Config, ConfigBuilder};
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::text_normalizer::TextNormalizer;

use crate::errors::sudachi_error;
use crate::morpheme::{
    data_from_single, dictionary_id_of, rb_morpheme_from_data, MorphemeData, PrefixMap,
};
use crate::parsing::{parse_mode, parse_subset, parse_user_dicts};
use crate::tokenizer::RbTokenizer;

fn build_dictionary_config(
    config_path: Option<String>,
    system_dict_path: Option<String>,
    user_dicts: Vec<String>,
) -> Result<Config, Error> {
    let mut builder = ConfigBuilder::from_opt_file(config_path.as_deref().map(Path::new))
        .map_err(sudachi_error)?;

    if let Some(system_dict_path) = system_dict_path {
        builder = builder.system_dict(system_dict_path);
    }

    for user_dict in user_dicts {
        builder = builder.user_dict(user_dict);
    }

    // sudachi.rs 0.7 embeds char.def and friends but only consults them when
    // asked, so a config that names no resource directory still resolves.
    Ok(builder.push_embedded().build())
}

#[magnus::wrap(class = "Kabosu::Dictionary")]
pub(crate) struct RbDictionary {
    inner: Arc<JapaneseDictionary>,
}

impl RbDictionary {
    pub(crate) fn new(
        config_path: Option<String>,
        system_dict_path: Option<String>,
        user_dicts_value: Option<Value>,
    ) -> Result<Self, Error> {
        let user_dicts = parse_user_dicts(user_dicts_value)?;
        let cfg = build_dictionary_config(config_path, system_dict_path, user_dicts)?;
        let dict = JapaneseDictionary::from_cfg(&cfg).map_err(sudachi_error)?;

        Ok(Self {
            inner: Arc::new(dict),
        })
    }

    // Prefix lookup over the query AFTER the dictionary's input-text plugins,
    // as sudachi.rs 0.7 does (so ｶﾎﾞｽ and ＡＢＣ find their entries). Each hit's
    // end is in normalized bytes and is mapped back onto the original text.
    pub(crate) fn lookup(&self, text: String) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let ary = ruby.ary_new();
        let lexicon = self.inner.lexicon();

        let normalized = TextNormalizer::from_shared_dictionary(self.inner.clone())
            .normalize(&text)
            .map_err(sudachi_error)?;
        let prefixes = PrefixMap::new(&self.inner, &text)?;

        for entry in lexicon.lookup(normalized.as_bytes(), 0) {
            let info = lexicon
                .get_word_info(entry.word_id)
                .map_err(sudachi_error)?;
            let end_c = prefixes.char_end(0, entry.end);
            let end = prefixes.byte_boundaries[end_c];

            let data = MorphemeData {
                surface: text[..end].to_string(),
                dictionary_form: info.dictionary_form(lexicon).to_string(),
                normalized_form: info.normalized_form(lexicon).to_string(),
                reading_form: info.reading_form(lexicon).to_string(),
                pos_id: info.pos_id(),
                word_id_raw: entry.word_id.as_raw(),
                is_oov: entry.word_id.is_oov(),
                dictionary_id: dictionary_id_of(entry.word_id),
                is_system: entry.word_id.is_system(),
                is_user: entry.word_id.is_user(),
                begin: 0,
                end,
                begin_c: 0,
                end_c,
                total_cost: 0,
                head_word_length: info.index_form_length(),
            };
            ary.push(rb_morpheme_from_data(data, self.inner.clone(), false))?;
        }

        Ok(ary)
    }

    /// Yields every public lexicon entry (system dictionary first, then each
    /// user dictionary) as a standalone morpheme.
    pub(crate) fn each_entry(ruby: &Ruby, rb_self: &Self) -> Result<Value, Error> {
        for entry in rb_self.inner.entries() {
            let single = entry.map_err(sudachi_error)?;
            let morpheme =
                rb_morpheme_from_data(data_from_single(&single), rb_self.inner.clone(), false);
            let _: Value = ruby.yield_value(morpheme)?;
        }
        Ok(ruby.qnil().as_value())
    }

    /// Every entry whose normalized headword equals the normalized `surface`,
    /// found by scanning the whole lexicon, so entries that are not indexed for
    /// lookup are found too. Slow on large dictionaries.
    pub(crate) fn lookup_all_entries(&self, surface: String) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let found = self
            .inner
            .lookup_all_entries(&surface)
            .map_err(sudachi_error)?;
        let ary = ruby.ary_new_capa(found.len());
        for single in &found {
            ary.push(rb_morpheme_from_data(
                data_from_single(single),
                self.inner.clone(),
                false,
            ))?;
        }
        Ok(ary)
    }

    pub(crate) fn oov_morpheme(
        &self,
        pos_id: u16,
        surface: String,
        reading: Option<String>,
        normalized_form: Option<String>,
        dictionary_form: Option<String>,
    ) -> Result<crate::morpheme::RbMorpheme, Error> {
        let single = self
            .inner
            .oov_morpheme_with_forms(
                pos_id,
                &surface,
                reading.as_deref().unwrap_or(&surface),
                normalized_form.as_deref().unwrap_or(&surface),
                dictionary_form.as_deref().unwrap_or(&surface),
            )
            .map_err(sudachi_error)?;
        Ok(rb_morpheme_from_data(
            data_from_single(&single),
            self.inner.clone(),
            false,
        ))
    }

    /// The text after this dictionary's input-text plugins: what tokenization
    /// and lookup actually match against.
    pub(crate) fn normalize(&self, text: String) -> Result<String, Error> {
        TextNormalizer::from_shared_dictionary(self.inner.clone())
            .normalize(&text)
            .map_err(sudachi_error)
    }

    pub(crate) fn create(
        &self,
        mode_str: Option<String>,
        fields: Option<Value>,
        debug: Option<bool>,
    ) -> Result<RbTokenizer, Error> {
        let subset = parse_subset(fields)?;
        let mode = parse_mode(mode_str.as_deref())?;
        Ok(RbTokenizer::new(
            self.inner.clone(),
            mode,
            subset,
            debug.unwrap_or(false),
        ))
    }
}
