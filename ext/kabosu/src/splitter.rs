use magnus::{Error, RArray, Ruby};
use std::ffi::c_void;
use sudachi::config::Config;
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::sentence_splitter::{SentenceSplitter, SplitSentences};

use crate::errors::sudachi_error;
use crate::nogvl::run_without_gvl;

struct SentenceChunk {
    start: usize,
    end: usize,
    sentence: String,
}

struct SplitSentencesJob {
    text: String,
    limit: Option<usize>,
    dict_path: Option<String>,
    out: Option<Result<Vec<SentenceChunk>, String>>,
}

impl SplitSentencesJob {
    fn run(&self) -> Result<Vec<SentenceChunk>, String> {
        let mut chunks = Vec::new();

        let mut push = |start: usize, end: usize, sentence: &str| {
            chunks.push(SentenceChunk {
                start,
                end,
                sentence: sentence.to_string(),
            });
        };

        match &self.dict_path {
            Some(path) => {
                let cfg = Config::new(None, None, Some(path.clone().into()))
                    .map_err(|e| e.to_string())?;
                let dict = JapaneseDictionary::from_cfg(&cfg).map_err(|e| e.to_string())?;
                let base = match self.limit {
                    Some(lim) => SentenceSplitter::with_limit(lim),
                    None => SentenceSplitter::new(),
                };
                let splitter = base.with_checker(dict.lexicon());
                for (range, sentence) in splitter.split(&self.text) {
                    push(range.start, range.end, sentence);
                }
            }
            None => {
                let splitter = match self.limit {
                    Some(lim) => SentenceSplitter::with_limit(lim),
                    None => SentenceSplitter::new(),
                };
                for (range, sentence) in splitter.split(&self.text) {
                    push(range.start, range.end, sentence);
                }
            }
        }

        Ok(chunks)
    }
}

unsafe extern "C" fn split_without_gvl(ptr: *mut c_void) -> *mut c_void {
    let job = unsafe { &mut *(ptr as *mut SplitSentencesJob) };
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| job.run()));
    job.out = Some(match outcome {
        Ok(result) => result,
        Err(panic_payload) => {
            let msg = if let Some(s) = panic_payload.downcast_ref::<&str>() {
                format!("panic during sentence split: {s}")
            } else if let Some(s) = panic_payload.downcast_ref::<String>() {
                format!("panic during sentence split: {s}")
            } else {
                "panic during sentence split".to_string()
            };
            Err(msg)
        }
    });
    std::ptr::null_mut()
}

fn split_sentences_impl(
    text: String,
    limit: Option<usize>,
    dict_path: Option<String>,
    with_ranges: bool,
) -> Result<RArray, Error> {
    let mut job = SplitSentencesJob {
        text,
        limit,
        dict_path,
        out: None,
    };
    run_without_gvl(&mut job, split_without_gvl);
    let chunks = match job
        .out
        .take()
        .unwrap_or_else(|| Err("sentence split job did not produce a result".to_string()))
    {
        Ok(chunks) => chunks,
        Err(msg) => return Err(sudachi_error(msg)),
    };

    let ruby = Ruby::get().unwrap();
    let result = ruby.ary_new_capa(chunks.len());
    for chunk in chunks {
        if with_ranges {
            let entry = ruby.ary_new_capa(3);
            entry.push(chunk.start)?;
            entry.push(chunk.end)?;
            entry.push(ruby.str_new(&chunk.sentence))?;
            result.push(entry)?;
        } else {
            result.push(ruby.str_new(&chunk.sentence))?;
        }
    }

    Ok(result)
}

pub(crate) fn split_sentences(
    text: String,
    limit: Option<usize>,
    dict_path: Option<String>,
) -> Result<RArray, Error> {
    split_sentences_impl(text, limit, dict_path, false)
}

pub(crate) fn split_sentences_with_ranges(
    text: String,
    limit: Option<usize>,
    dict_path: Option<String>,
) -> Result<RArray, Error> {
    split_sentences_impl(text, limit, dict_path, true)
}
