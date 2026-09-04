# Benchmarks

`./bench/run.sh` measures this library, the Rust `aho-corasick` crate
(its default configuration, which may pick a DFA and a SIMD prefilter,
and its bare non-contiguous NFA with the prefilter off, the closest
structural match to this library), ahocorasick_rs and pyahocorasick on
the same corpora, in the same search modes, and cross-checks the match
counts between them. Results and discussion are on the
[performance page](https://ville.dev/ocaml-aho-corasick/performance.html).

## What runs

| workload | patterns | haystack | recorded count |
|---|---|---|---|
| `sherlock/names-2` | Sherlock, Holmes | The Adventures of Sherlock Holmes (594 KB) | 558 |
| `sherlock/names-7` | seven character names | same | 740 |
| `sherlock/prefixes` | Sher, Hol | same | 582 |
| `sherlock/absent` | five names that never occur | same | 0 |
| `sherlock/words-5000` | 5 000 English words | same | |
| `sherlock/words-15000` | 15 000 English words | same | |
| `opensubtitles/names-5` | five full names | OpenSubtitles English sample (899 KB) | 714 |
| `opensubtitles/dictionary-15` | 2 663 words of 15+ letters | same | 15 |
| `opensubtitles/byte-a` | a | same | 47 062 |
| `opensubtitles/bytes-8` | a b t e i o c g | same | 309 829 |
| `dense/abc-1m` | every string of 1 to 3 letters over abc (39) | 1 MiB random abc text | |
| `sparse/bytes-1m` | 100 random 8-byte printable strings | 1 MiB random bytes | |
| `pathological/suffixes` | a, aa, ..., a^20 | 200 000 a's | |
| `scaling/abc-*` | the 39 abc patterns | 64 KiB, 256 KiB, 1 MiB, 4 MiB of abc text | |

The real-text corpora and word lists are the ones the Rust crate's
[rebar](https://github.com/BurntSushi/rebar) benchmark suite uses,
fetched by `fetch-corpora.sh` from a pinned commit and checked against
their SHA-256; the recorded counts are the ones rebar's definitions
carry for those pattern sets on those bytes, which the Rust crate and
daachorse have been checked against. The synthetic corpora come from
`synth.py`, deterministically. `workloads.tsv` defines the set.

Each implementation runs every mode it offers: overlapping search,
standard non-overlapping search, leftmost-longest, membership,
replacement, and the streamed forms with 4 KiB chunks. A measurement
builds the automaton once (timed separately), runs the search until at
least `SECONDS_PER_RUN` seconds and three runs have elapsed, and reports
the median run. Throughput is haystack bytes divided by that median.
The drivers are the `bench` subcommand of the differential-test drivers
in `compat/`, so what is timed is exactly what the differential test
checks for agreement.

## Reading the numbers

- Every row's match count must agree across implementations, the
  streamed and lazy modes must agree with the modes they mirror, and a
  workload with a recorded count must reproduce it in standard mode;
  `report.py` exits non-zero otherwise. A benchmark whose counts differ
  is measuring different work.
- `is_match` stops at the first hit, so its rate is shown only for
  workloads with no match; elsewhere the cell says "early exit".
- The Rust default engine's figures on few-pattern workloads come from
  its SIMD prefilter (Teddy), which scans for candidate bytes without
  running the automaton; its NFA column is the automaton alone.
- The Python figures include the interpreter's cost of producing a
  Python object per match, which is what a Python caller pays.
- `overlapping` in the OCaml column is `find_all`, which materialises a
  list; `overlapping_iter` is `find_iter`, consumed lazily. On
  match-dense inputs the difference is the cost of keeping millions of
  records live.

## Running it

```sh
SECONDS_PER_RUN=2 opam exec -- ./bench/run.sh      # everything, results in bench/_out/
WORKLOADS=workloads-smoke.tsv opam exec -- ./bench/run.sh
python3 bench/report.py bench/_out/results.tsv --workloads bench/workloads.tsv --env bench/_out/env.txt --html
python3 bench/compare.py before/results.tsv after/results.tsv   # this library, before and after a change
```

Needs dune, cargo, curl and Python 3; pyahocorasick and ahocorasick_rs
are included when importable. CI runs the smoke workload so the scripts
stay working and one recorded count is cross-checked on every push.
`results/` keeps the report of each published run, named by date and
architecture.
