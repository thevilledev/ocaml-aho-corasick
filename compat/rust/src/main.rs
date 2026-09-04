//! Differential-test and benchmark driver for the `aho-corasick` crate.
//!
//! `cases`  reads cases from stdin and prints one result line per case
//!          and mode; `../README.md` describes both formats.
//! `bench`  times one search mode over a patterns file and a haystack
//!          file and prints one tab-separated result line.
//!
//! Every driver under `compat/` speaks the same formats, so the outputs
//! can be diffed directly.

use std::io::{self, BufRead, Read, Write};
use std::time::Instant;

use aho_corasick::{AhoCorasick, AhoCorasickKind, Match, MatchKind};

fn usage() -> ! {
    eprintln!(
        "usage: aho-corasick-compat cases < cases.tsv\n       \
         aho-corasick-compat bench <mode> <patterns-file> <haystack-file> \
         [--seconds S] [--chunk N] [--engine default|nfa]"
    );
    std::process::exit(2)
}

fn hex_decode(s: &str) -> Vec<u8> {
    assert!(s.len() % 2 == 0, "odd-length hex: {s:?}");
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).expect("bad hex"))
        .collect()
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

struct Case {
    id: String,
    ignore_case: bool,
    patterns: Vec<Vec<u8>>,
    input: Vec<u8>,
    chunks: Vec<usize>,
}

fn parse_case(line: &str) -> Option<Case> {
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    let f: Vec<&str> = line.split('\t').collect();
    assert_eq!(f.len(), 5, "malformed case line: {line:?}");
    let patterns = if f[2].is_empty() {
        Vec::new()
    } else {
        f[2].split(',').map(hex_decode).collect()
    };
    let chunks = if f[4].is_empty() {
        Vec::new()
    } else {
        f[4].split(',').map(|n| n.parse().expect("chunk size")).collect()
    };
    Some(Case {
        id: f[0].to_string(),
        ignore_case: f[1].contains('i'),
        patterns,
        input: hex_decode(f[3]),
        chunks,
    })
}

/// Cut `input` at the given sizes; whatever remains is a final chunk.
fn split_chunks(input: &[u8], sizes: &[usize]) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    let mut pos = 0;
    for &size in sizes {
        let take = size.min(input.len() - pos);
        out.push(input[pos..pos + take].to_vec());
        pos += take;
    }
    out.push(input[pos..].to_vec());
    out
}

/// Hands out the input one chunk per `read` call, so the stream searcher
/// sees the same boundaries as the other drivers.
struct ChunkReader {
    chunks: Vec<Vec<u8>>,
    index: usize,
    offset: usize,
}

impl Read for ChunkReader {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        while self.index < self.chunks.len() {
            let chunk = &self.chunks[self.index];
            if self.offset >= chunk.len() {
                self.index += 1;
                self.offset = 0;
                continue;
            }
            let n = (chunk.len() - self.offset).min(buf.len());
            buf[..n].copy_from_slice(&chunk[self.offset..self.offset + n]);
            self.offset += n;
            return Ok(n);
        }
        Ok(0)
    }
}

/// Hands out a slice `chunk` bytes at a time, without allocating.
struct SliceReader<'a> {
    data: &'a [u8],
    pos: usize,
    chunk: usize,
}

impl Read for SliceReader<'_> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let n = self.chunk.min(buf.len()).min(self.data.len() - self.pos);
        buf[..n].copy_from_slice(&self.data[self.pos..self.pos + n]);
        self.pos += n;
        Ok(n)
    }
}

fn triple(m: &Match) -> (usize, usize, usize) {
    (m.pattern().as_usize(), m.start(), m.end())
}

fn fmt_matches(ms: &[(usize, usize, usize)]) -> String {
    if ms.is_empty() {
        "-".to_string()
    } else {
        ms.iter()
            .map(|(p, s, e)| format!("{p}:{s}:{e}"))
            .collect::<Vec<_>>()
            .join(" ")
    }
}

#[derive(Clone, Copy)]
enum Engine {
    /// The crate's defaults: it picks the automaton and may use a prefilter.
    Default,
    /// The plain non-contiguous NFA with no prefilter: the bare automaton.
    Nfa,
}

fn build(patterns: &[Vec<u8>], kind: MatchKind, ignore_case: bool, engine: Engine) -> AhoCorasick {
    let mut builder = AhoCorasick::builder();
    builder.match_kind(kind).ascii_case_insensitive(ignore_case);
    if let Engine::Nfa = engine {
        builder.kind(Some(AhoCorasickKind::NoncontiguousNFA)).prefilter(false);
    }
    builder.build(patterns).expect("build")
}

fn run_cases() {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    for line in stdin.lock().lines() {
        let line = line.expect("stdin");
        let Some(c) = parse_case(&line) else { continue };
        let standard = build(&c.patterns, MatchKind::Standard, c.ignore_case, Engine::Default);
        let longest = build(&c.patterns, MatchKind::LeftmostLongest, c.ignore_case, Engine::Default);
        let mut emit = |mode: &str, result: String| {
            writeln!(out, "{}\t{}\t{}", c.id, mode, result).expect("stdout")
        };

        let ms: Vec<_> = standard.find_overlapping_iter(&c.input).map(|m| triple(&m)).collect();
        emit("overlapping", fmt_matches(&ms));

        let ms: Vec<_> = standard.find_iter(&c.input).map(|m| triple(&m)).collect();
        emit("standard", fmt_matches(&ms));

        let reader = ChunkReader { chunks: split_chunks(&c.input, &c.chunks), index: 0, offset: 0 };
        let ms: Vec<_> = standard
            .stream_find_iter(reader)
            .map(|m| triple(&m.expect("stream")))
            .collect();
        emit("standard_stream", fmt_matches(&ms));

        let ms: Vec<_> = longest.find_iter(&c.input).map(|m| triple(&m)).collect();
        emit("leftmost_longest", fmt_matches(&ms));

        let replacements: Vec<Vec<u8>> =
            (0..c.patterns.len()).map(|i| format!("<{i}>").into_bytes()).collect();
        emit("replace", hex_encode(&longest.replace_all_bytes(&c.input, &replacements)));

        emit("is_match", standard.is_match(&c.input).to_string());

        let first: Vec<_> = standard.find(&c.input).iter().map(triple).collect();
        emit("first", fmt_matches(&first));

        let first: Vec<_> = longest.find(&c.input).iter().map(triple).collect();
        emit("first_leftmost_longest", fmt_matches(&first));
    }
}

fn read_patterns(path: &str) -> Vec<Vec<u8>> {
    let data = std::fs::read(path).expect("patterns file");
    data.split(|&b| b == b'\n')
        .filter(|line| !line.is_empty())
        .map(|line| line.to_vec())
        .collect()
}

fn run_bench(args: &[String]) {
    if args.len() < 3 {
        usage()
    }
    let mode = args[0].as_str();
    let patterns = read_patterns(&args[1]);
    let haystack = std::fs::read(&args[2]).expect("haystack file");
    let mut seconds = 2.0f64;
    let mut chunk = 4096usize;
    let mut engine = Engine::Default;
    let mut i = 3;
    while i + 1 < args.len() {
        match args[i].as_str() {
            "--seconds" => seconds = args[i + 1].parse().expect("--seconds"),
            "--chunk" => chunk = args[i + 1].parse().expect("--chunk"),
            "--engine" => {
                engine = match args[i + 1].as_str() {
                    "default" => Engine::Default,
                    "nfa" => Engine::Nfa,
                    _ => usage(),
                }
            }
            _ => usage(),
        }
        i += 2;
    }
    if i != args.len() {
        usage()
    }
    let kind = match mode {
        "leftmost_longest" | "replace" => MatchKind::LeftmostLongest,
        _ => MatchKind::Standard,
    };
    let started = Instant::now();
    let ac = build(&patterns, kind, false, engine);
    let build_ns = started.elapsed().as_nanos();
    let replacements: Vec<Vec<u8>> =
        (0..patterns.len()).map(|i| format!("<{i}>").into_bytes()).collect();
    let run = || -> usize {
        match mode {
            "overlapping" => ac.find_overlapping_iter(&haystack).count(),
            "standard" | "leftmost_longest" => ac.find_iter(&haystack).count(),
            "is_match" => ac.is_match(&haystack) as usize,
            "replace" => ac.replace_all_bytes(&haystack, &replacements).len(),
            "standard_stream" => {
                let reader = SliceReader { data: &haystack, pos: 0, chunk };
                ac.stream_find_iter(reader).count()
            }
            _ => usage(),
        }
    };
    let count = run();
    let mut samples: Vec<u128> = Vec::new();
    let started = Instant::now();
    while started.elapsed().as_secs_f64() < seconds || samples.len() < 3 {
        let t = Instant::now();
        let c = run();
        samples.push(t.elapsed().as_nanos());
        assert_eq!(c, count, "count changed between runs");
    }
    samples.sort();
    let name = match engine {
        Engine::Default => "rust/aho-corasick/default",
        Engine::Nfa => "rust/aho-corasick/nfa",
    };
    println!(
        "{name}\t{mode}\t{}\t{}\t{build_ns}\t{}\t{}\t{count}",
        haystack.len(),
        samples.len(),
        samples[0],
        samples[samples.len() / 2]
    );
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("cases") => run_cases(),
        Some("bench") => run_bench(&args[2..]),
        _ => usage(),
    }
}
