use magnus::{Error, RArray, Ruby};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use sudachi::analysis::stateful_tokenizer::StatefulTokenizer;
use sudachi::analysis::Mode;
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::dic::subset::InfoSubset;
use sudachi::prelude::MorphemeList;

use crate::errors::sudachi_error;
use crate::morpheme::{build_morpheme_data, MorphemeData};
use crate::nogvl::run_without_gvl;
use crate::parsing::subset_to_array;
use crate::token_batch::RbTokenBatch;

struct ThreadTokenizerPool {
    id: usize,
    dict: Arc<JapaneseDictionary>,
    mode: Mode,
}

impl ThreadTokenizerPool {
    fn new(dict: Arc<JapaneseDictionary>, mode: Mode) -> Self {
        Self {
            id: NEXT_POOL_ID.fetch_add(1, Ordering::Relaxed),
            dict,
            mode,
        }
    }
}

static NEXT_POOL_ID: AtomicUsize = AtomicUsize::new(1);

thread_local! {
    static TOKENIZER_CACHE: RefCell<HashMap<usize, StatefulTokenizer<Arc<JapaneseDictionary>>>> =
        RefCell::new(HashMap::new());
}

struct AnalyzeOutput {
    morphemes: Vec<MorphemeData>,
    internal_cost: i32,
}

struct AnalyzeJob<'a> {
    pool: &'a ThreadTokenizerPool,
    subset: InfoSubset,
    debug: bool,
    text: String,
    out: Option<Result<AnalyzeOutput, String>>,
}

impl AnalyzeJob<'_> {
    fn run(&self) -> Result<AnalyzeOutput, String> {
        analyze_text(self.pool, self.subset, self.debug, &self.text)
    }
}

unsafe extern "C" fn analyze_without_gvl(ptr: *mut c_void) -> *mut c_void {
    let job = unsafe { &mut *(ptr as *mut AnalyzeJob<'_>) };
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| job.run()));
    job.out = Some(match outcome {
        Ok(result) => result,
        Err(panic_payload) => {
            let msg = if let Some(s) = panic_payload.downcast_ref::<&str>() {
                format!("panic during tokenization: {s}")
            } else if let Some(s) = panic_payload.downcast_ref::<String>() {
                format!("panic during tokenization: {s}")
            } else {
                "panic during tokenization".to_string()
            };
            Err(msg)
        }
    });
    std::ptr::null_mut()
}

fn analyze_text(
    pool: &ThreadTokenizerPool,
    subset: InfoSubset,
    debug: bool,
    text: &str,
) -> Result<AnalyzeOutput, String> {
    TOKENIZER_CACHE.with(|cache| {
        let mut cache = cache.borrow_mut();
        let tokenizer = cache
            .entry(pool.id)
            .or_insert_with(|| StatefulTokenizer::new(pool.dict.clone(), pool.mode));

        tokenizer.set_debug(debug);
        tokenizer.set_subset(subset);
        tokenizer.reset().push_str(text);
        tokenizer.do_tokenize().map_err(|e| e.to_string())?;

        let mut mlist = MorphemeList::empty(pool.dict.clone());
        mlist
            .collect_results(tokenizer)
            .map_err(|e| e.to_string())?;

        let mut morphemes = Vec::with_capacity(mlist.len());
        for i in 0..mlist.len() {
            morphemes.push(build_morpheme_data(&mlist.get(i)));
        }

        Ok(AnalyzeOutput {
            morphemes,
            internal_cost: mlist.get_internal_cost(),
        })
    })
}

fn assert_send_sync<T: Send + Sync>() {}

fn assert_thread_safety() {
    assert_send_sync::<Arc<JapaneseDictionary>>();
    assert_send_sync::<ThreadTokenizerPool>();
}

#[magnus::wrap(class = "Kabosu::Tokenizer")]
pub(crate) struct RbTokenizer {
    pool: ThreadTokenizerPool,
    mode: Mode,
    debug: bool,
    subset: InfoSubset,
    last_internal_cost: Cell<i32>,
}

impl RbTokenizer {
    pub(crate) fn new(
        dict: Arc<JapaneseDictionary>,
        mode: Mode,
        subset: InfoSubset,
        debug: bool,
    ) -> Self {
        assert_thread_safety();

        Self {
            pool: ThreadTokenizerPool::new(dict, mode),
            mode,
            debug,
            subset,
            last_internal_cost: Cell::new(0),
        }
    }

    fn analyze(&self, text: String) -> Result<AnalyzeOutput, Error> {
        let mut job = AnalyzeJob {
            pool: &self.pool,
            subset: self.subset,
            debug: self.debug,
            text,
            out: None,
        };

        run_without_gvl(&mut job, analyze_without_gvl);

        match job
            .out
            .take()
            .unwrap_or_else(|| Err("tokenization job did not produce a result".to_string()))
        {
            Ok(output) => {
                self.last_internal_cost.set(output.internal_cost);
                Ok(output)
            }
            Err(msg) => Err(sudachi_error(msg)),
        }
    }

    pub(crate) fn tokenize(&self, text: String) -> Result<RbTokenBatch, Error> {
        let analyzed = self.analyze(text)?;
        Ok(RbTokenBatch::new(
            analyzed.morphemes,
            self.pool.dict.clone(),
            self.debug,
            analyzed.internal_cost,
        ))
    }

    pub(crate) fn mode(&self) -> String {
        self.mode.to_string()
    }

    pub(crate) fn fields(&self) -> Result<RArray, Error> {
        let ruby = Ruby::get().unwrap();
        subset_to_array(&ruby, self.subset)
    }

    pub(crate) fn is_debug(&self) -> bool {
        self.debug
    }

    pub(crate) fn internal_cost(&self) -> i32 {
        self.last_internal_cost.get()
    }
}
