use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::Instant;

use sudachi::analysis::stateless_tokenizer::StatelessTokenizer;
use sudachi::analysis::{Mode, Tokenize};
use sudachi::config::Config;
use sudachi::dic::dictionary::JapaneseDictionary;
use sudachi::sentence_splitter::{SentenceSplitter, SplitSentences};

fn bench(tokenizer: &StatelessTokenizer<&JapaneseDictionary>, splitter: &SentenceSplitter, text: &str, mode: Mode, label: &str, iterations: usize) {
    let start = Instant::now();
    for _ in 0..iterations {
        for (_range, sentence) in splitter.split(text) {
            let _ = tokenizer.tokenize(sentence, mode, false).unwrap();
        }
    }
    let elapsed = start.elapsed().as_secs_f64();
    println!("{label}:  {elapsed:>8.3}s  ({iterations} iterations)");
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: kabosu-bench <fixture_path> [dict_path]");
        std::process::exit(1);
    }

    let fixture_path = &args[1];
    let dict_path = args.get(2).map(PathBuf::from);

    let text = fs::read_to_string(fixture_path).expect("Failed to read fixture file");

    println!("sudachi.rs benchmark (raw Rust, no Ruby overhead)");
    println!("Input: {} ({} bytes)", fixture_path, text.len());
    println!();

    let cfg = Config::new(None, None, dict_path).expect("Failed to create config");
    let dict = JapaneseDictionary::from_cfg(&cfg).expect("Failed to load dictionary");
    let tokenizer = StatelessTokenizer::new(&dict);
    let splitter = SentenceSplitter::new();
    let iterations = 10;

    bench(&tokenizer, &splitter, &text, Mode::C, "tokenize (sentences, mode C)", iterations);
    bench(&tokenizer, &splitter, &text, Mode::A, "tokenize (sentences, mode A)", iterations);
    bench(&tokenizer, &splitter, &text, Mode::B, "tokenize (sentences, mode B)", iterations);

    println!();
    let start = Instant::now();
    for _ in 0..iterations {
        for (_range, sentence) in splitter.split(&text) {
            let _ = tokenizer.tokenize(sentence, Mode::C, false).unwrap();
        }
    }
    let elapsed = start.elapsed().as_secs_f64();
    let mb = (text.len() * iterations) as f64 / (1024.0 * 1024.0);
    println!("Throughput: {:.2} MB/s", mb / elapsed);
}
