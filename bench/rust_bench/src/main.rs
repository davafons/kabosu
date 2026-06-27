use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use std::thread;
use std::time::Instant;

use sudachi::analysis::stateless_tokenizer::StatelessTokenizer;
use sudachi::analysis::{Mode, Tokenize};
use sudachi::config::Config;
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::sentence_splitter::{SentenceSplitter, SplitSentences};

fn bench_split(splitter: &SentenceSplitter, text: &str, iterations: usize) {
    let start = Instant::now();
    for _ in 0..iterations {
        for (_range, _sentence) in splitter.split(text) {}
    }
    let elapsed = start.elapsed().as_secs_f64();
    println!("split_sentences:  {elapsed:>8.3}s  ({iterations} iterations)");
}

fn bench_tokenize(
    tokenizer: &StatelessTokenizer<Arc<JapaneseDictionary>>,
    sentences: &[&str],
    mode: Mode,
    label: &str,
    iterations: usize,
) {
    let start = Instant::now();
    for _ in 0..iterations {
        for sentence in sentences {
            let _ = tokenizer.tokenize(sentence, mode, false).unwrap();
        }
    }
    let elapsed = start.elapsed().as_secs_f64();
    println!("{label}:  {elapsed:>8.3}s  ({iterations} iterations)");
}

fn bench_tokenize_mt(
    dict: Arc<JapaneseDictionary>,
    sentences: Arc<Vec<String>>,
    mode: Mode,
    threads: usize,
    requests_per_thread: usize,
) {
    let total_requests = threads * requests_per_thread;

    // Shared tokenizer across all threads (Rails-like shared object access).
    let shared_tokenizer = Arc::new(StatelessTokenizer::new(dict.clone()));
    let start = Instant::now();
    let mut handles = Vec::with_capacity(threads);

    for tid in 0..threads {
        let tokenizer = shared_tokenizer.clone();
        let sentences = sentences.clone();
        handles.push(thread::spawn(move || {
            let mut bytes = 0usize;
            let len = sentences.len();
            for i in 0..requests_per_thread {
                let idx = (tid + i * 7919) % len;
                let sentence = &sentences[idx];
                let _ = tokenizer.as_ref().tokenize(sentence, mode, false).unwrap();
                bytes += sentence.len();
            }
            bytes
        }));
    }

    let mut total_bytes_shared = 0usize;
    for h in handles {
        total_bytes_shared += h.join().expect("worker thread panicked");
    }

    let elapsed_shared = start.elapsed().as_secs_f64();
    let mb_shared = total_bytes_shared as f64 / (1024.0 * 1024.0);
    println!(
        "shared tok:      {elapsed_shared:>8.3}s  ({threads} threads x {requests_per_thread} req)"
    );
    println!(
        "Throughput ST: {:.2} MB/s (shared tokenizer)",
        mb_shared / elapsed_shared
    );

    // Per-thread tokenizer baseline.
    let start = Instant::now();
    let mut handles = Vec::with_capacity(threads);

    for tid in 0..threads {
        let dict = dict.clone();
        let sentences = sentences.clone();
        handles.push(thread::spawn(move || {
            let tokenizer = StatelessTokenizer::new(dict);
            let mut bytes = 0usize;
            let len = sentences.len();
            for i in 0..requests_per_thread {
                let idx = (tid + i * 7919) % len;
                let sentence = &sentences[idx];
                let _ = tokenizer.tokenize(sentence, mode, false).unwrap();
                bytes += sentence.len();
            }
            bytes
        }));
    }

    let mut total_bytes_per_thread = 0usize;
    for h in handles {
        total_bytes_per_thread += h.join().expect("worker thread panicked");
    }

    let elapsed_per_thread = start.elapsed().as_secs_f64();
    let mb_per_thread = total_bytes_per_thread as f64 / (1024.0 * 1024.0);
    println!(
        "per-thread tok:  {elapsed_per_thread:>8.3}s  ({threads} threads x {requests_per_thread} req)"
    );
    println!(
        "Throughput PT: {:.2} MB/s (tokenizer per thread)",
        mb_per_thread / elapsed_per_thread
    );
    println!("Total requests: {total_requests}");
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!(
            "Usage: kabosu-bench <fixture_path> [dict_path] [--mt <threads> <requests_per_thread>]"
        );
        std::process::exit(1);
    }

    let fixture_path = &args[1];
    let mut dict_path = None;
    let mut mt: Option<(usize, usize)> = None;
    let mut idx = 2usize;

    if idx < args.len() && args[idx] != "--mt" {
        dict_path = Some(PathBuf::from(&args[idx]));
        idx += 1;
    }

    if idx < args.len() {
        if args[idx] != "--mt" || idx + 2 >= args.len() {
            eprintln!("Invalid arguments. Usage: kabosu-bench <fixture_path> [dict_path] [--mt <threads> <requests_per_thread>]");
            std::process::exit(1);
        }
        let threads = args[idx + 1]
            .parse::<usize>()
            .expect("threads must be a positive integer");
        let requests = args[idx + 2]
            .parse::<usize>()
            .expect("requests_per_thread must be a positive integer");
        mt = Some((threads, requests));
    }

    let text = fs::read_to_string(fixture_path).expect("Failed to read fixture file");

    println!("sudachi.rs benchmark (raw Rust, no Ruby overhead)");
    println!("Input: {} ({} bytes)", fixture_path, text.len());
    println!();

    let cfg = Config::new(None, None, dict_path).expect("Failed to create config");
    let dict = Arc::new(JapaneseDictionary::from_cfg(&cfg).expect("Failed to load dictionary"));
    let tokenizer = StatelessTokenizer::new(dict.clone());
    let splitter = SentenceSplitter::new();
    let iterations = 10;

    // Pre-split for tokenization-only benchmarks
    let sentences: Vec<&str> = splitter.split(&text).map(|(_range, s)| s).collect();

    println!("── Sentence splitting ──");
    println!();
    bench_split(&splitter, &text, iterations);

    println!();
    println!("── Tokenization ──");
    println!();
    bench_tokenize(&tokenizer, &sentences, Mode::C, "mode C", iterations);
    bench_tokenize(&tokenizer, &sentences, Mode::A, "mode A", iterations);
    bench_tokenize(&tokenizer, &sentences, Mode::B, "mode B", iterations);

    println!();
    let start = Instant::now();
    for _ in 0..iterations {
        for sentence in &sentences {
            let _ = tokenizer.tokenize(sentence, Mode::C, false).unwrap();
        }
    }
    let elapsed = start.elapsed().as_secs_f64();
    let mb = (text.len() * iterations) as f64 / (1024.0 * 1024.0);
    println!(
        "Throughput: {:.2} MB/s (mode C, {iterations} iterations)",
        mb / elapsed
    );

    if let Some((threads, requests_per_thread)) = mt {
        let mt_sentences: Vec<String> = sentences.iter().map(|s| (*s).to_string()).collect();
        println!();
        println!("── Tokenization (Multithread) ──");
        println!("shared tok: one tokenizer shared by all threads (Rails-style)");
        println!("per-thread tok: one tokenizer instance per worker thread");
        println!();
        bench_tokenize_mt(
            dict.clone(),
            Arc::new(mt_sentences),
            Mode::C,
            threads,
            requests_per_thread,
        );
    }
}
