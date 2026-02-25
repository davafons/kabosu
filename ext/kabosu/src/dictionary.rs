use magnus::{Error, RArray, Ruby, Value};
use std::path::Path;
use std::sync::Arc;
use sudachi::config::{Config, ConfigBuilder};
use sudachi::dic::dictionary::JapaneseDictionary;

use crate::errors::sudachi_error;
use crate::morpheme::{rb_morpheme_from_data, MorphemeData};
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

    Ok(builder.build())
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

    pub(crate) fn lookup(&self, text: String) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let ary = ruby.ary_new();
        let lexicon = self.inner.lexicon();

        for entry in lexicon.lookup(text.as_bytes(), 0) {
            let info = lexicon.get_word_info(entry.word_id).map_err(sudachi_error)?;
            let surface_slice = text.get(..entry.end).ok_or_else(|| {
                sudachi_error(format!(
                    "lookup returned invalid UTF-8 boundary: end={}",
                    entry.end
                ))
            })?;

            let data = MorphemeData {
                surface: surface_slice.to_string(),
                pos_id: info.pos_id(),
                word_id_raw: entry.word_id.as_raw(),
                is_oov: entry.word_id.is_oov(),
                dictionary_id: if entry.word_id.is_oov() {
                    -1
                } else {
                    entry.word_id.dic() as i32
                },
                is_system: entry.word_id.is_system(),
                is_user: entry.word_id.is_user(),
                begin: 0,
                end: entry.end,
                begin_c: 0,
                end_c: surface_slice.chars().count(),
                total_cost: 0,
            };
            ary.push(rb_morpheme_from_data(data, self.inner.clone(), false))?;
        }

        Ok(ary)
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
