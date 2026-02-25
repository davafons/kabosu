use magnus::{Error, RArray, Ruby};
use std::sync::Arc;
use sudachi::dic::dictionary::JapaneseDictionary;

use crate::morpheme::{rb_morpheme_from_data, MorphemeData, RbMorpheme};

#[magnus::wrap(class = "Kabosu::TokenBatch")]
pub(crate) struct RbTokenBatch {
    morphemes: Vec<MorphemeData>,
    dict: Arc<JapaneseDictionary>,
    debug: bool,
    internal_cost: i32,
}

impl RbTokenBatch {
    pub(crate) fn new(
        morphemes: Vec<MorphemeData>,
        dict: Arc<JapaneseDictionary>,
        debug: bool,
        internal_cost: i32,
    ) -> Self {
        Self {
            morphemes,
            dict,
            debug,
            internal_cost,
        }
    }

    pub(crate) fn size(&self) -> usize {
        self.morphemes.len()
    }

    pub(crate) fn internal_cost(&self) -> i32 {
        self.internal_cost
    }

    pub(crate) fn morpheme_at(&self, idx: usize) -> Option<RbMorpheme> {
        self.morphemes
            .get(idx)
            .cloned()
            .map(|data| rb_morpheme_from_data(data, self.dict.clone(), self.debug))
    }

    pub(crate) fn surfaces(&self) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        let ary = ruby.ary_new_capa(self.morphemes.len());
        for m in &self.morphemes {
            ary.push(ruby.str_new(&m.surface))?;
        }
        Ok(ary)
    }
}
