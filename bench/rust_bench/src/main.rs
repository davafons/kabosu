use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::Instant;

use sudachi::analysis::stateless_tokenizer::StatelessTokenizer;
use sudachi::analysis::{Mode, Tokenize};
use sudachi::config::Config;
use sudachi::dic::dictionary::JapaneseDictionary;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: kabosu-bench <fixture_path> [dict_path]");
        eprintln!();
        eprintln!("Example:");
        eprintln!("  cargo run --release -- ../fixtures/wagahai.txt");
        eprintln!("  cargo run --release -- ../fixtures/wagahai.txt ~/.kabosu/dict/small/system.dic");
        std::process::exit(1);
    }

    let fixture_path = &args[1];
    let dict_path = args.get(2).map(PathBuf::from);

    let text = fs::read_to_string(fixture_path).expect("Failed to read fixture file");
    let lines: Vec<&str> = text.lines().filter(|l| !l.is_empty()).collect();

    println!("sudachi.rs benchmark (raw Rust, no Ruby overhead)");
    println!(
        "Input: {} ({} bytes, {} lines)",
        fixture_path,
        text.len(),
        lines.len()
    );
    println!();

    // Load dictionary
    let start = Instant::now();
    let cfg = Config::new(None, None, dict_path).expect("Failed to create config");
    let dict = JapaneseDictionary::from_cfg(&cfg).expect("Failed to load dictionary");
    println!("Dictionary loaded in {:.3}s", start.elapsed().as_secs_f64());
    println!();

    let iterations = 10;
    let tokenizer = StatelessTokenizer::new(&dict);

    // Benchmark: full text, mode C
    let start = Instant::now();
    for _ in 0..iterations {
        let _ = tokenizer.tokenize(&text, Mode::C, false).unwrap();
    }
    let elapsed = start.elapsed().as_secs_f64();
    println!(
        "tokenize (full text, mode C):  {:>8.3}s  ({} iterations)",
        elapsed, iterations
    );

    // Benchmark: line-by-line, mode C
    let start = Instant::now();
    for _ in 0..iterations {
        for line in &lines {
            let _ = tokenizer.tokenize(line, Mode::C, false).unwrap();
        }
    }
    let elapsed = start.elapsed().as_secs_f64();
    println!(
        "tokenize (line-by-line, C):    {:>8.3}s  ({} iterations)",
        elapsed, iterations
    );

    // Benchmark: full text, mode A
    let start = Instant::now();
    for _ in 0..iterations {
        let _ = tokenizer.tokenize(&text, Mode::A, false).unwrap();
    }
    let elapsed = start.elapsed().as_secs_f64();
    println!(
        "tokenize (full text, mode A):  {:>8.3}s  ({} iterations)",
        elapsed, iterations
    );

    // Benchmark: full text, mode B
    let start = Instant::now();
    for _ in 0..iterations {
        let _ = tokenizer.tokenize(&text, Mode::B, false).unwrap();
    }
    let elapsed = start.elapsed().as_secs_f64();
    println!(
        "tokenize (full text, mode B):  {:>8.3}s  ({} iterations)",
        elapsed, iterations
    );

    // Throughput summary
    println!();
    let start = Instant::now();
    for _ in 0..iterations {
        let _ = tokenizer.tokenize(&text, Mode::C, false).unwrap();
    }
    let elapsed = start.elapsed().as_secs_f64();
    let mb = (text.len() * iterations) as f64 / (1024.0 * 1024.0);
    println!("Throughput: {:.2} MB/s (mode C, {} iterations)", mb / elapsed, iterations);
}
