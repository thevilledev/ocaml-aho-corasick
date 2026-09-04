# Differential testing against other Aho-Corasick implementations

This directory runs the library side by side with other Aho-Corasick
implementations on the same inputs and requires the answers to agree.
It is the automated check that the [compatibility
page](https://ville.dev/ocaml-aho-corasick/compatibility.html) used to
say did not exist.

| oracle | version | lineage |
|---|---|---|
| [Rust `aho-corasick`](https://github.com/BurntSushi/aho-corasick) | 1.1.5 | the reference implementation most others are measured against |
| [pyahocorasick](https://github.com/WojciechMula/pyahocorasick) | 2.3.1 | an independent C implementation |
| [ahocorasick_rs](https://github.com/G-Research/ahocorasick_rs) | 1.0.3 | Python binding to the Rust crate, byte-offset API |

`./compat/run.sh` generates the cases, builds and runs one driver per
implementation, and compares the outputs. It runs in CI on every push and
pull request (the `differential` job), so a change that makes this
library disagree with the Rust crate fails the build.

## What is compared

Every driver reads the same case file and prints the same result format,
so a comparison is a comparison of strings: identical means identical
pattern indices, identical half-open byte offsets, identical order.

| this library | Rust `aho-corasick` | pyahocorasick | ahocorasick_rs |
|---|---|---|---|
| `find_all` | `find_overlapping_iter` | `iter()` | `find_matches_as_indexes(overlapping=True)` |
| `Stream.feed`, chunked | `find_overlapping_iter` (no streaming counterpart) | `iter()` | as above |
| `Stream.feed_nonoverlapping`, whole input | `find_iter`, `MatchKind::Standard` | | `find_matches_as_indexes()` |
| `Stream.feed_nonoverlapping`, chunked | `stream_find_iter` over the same chunks | | |
| `find_leftmost_longest` | `find_iter`, `MatchKind::LeftmostLongest` | `iter_long()` | `MatchKind.LeftmostLongest` |
| `Stream.Leftmost_longest`, chunked | `find_iter`, `MatchKind::LeftmostLongest` | `iter_long()` | as above |
| `replace_all` | `replace_all_bytes`, `MatchKind::LeftmostLongest` | | |
| `Stream.Replace`, chunked | `replace_all_bytes` | | |
| `mem` | `is_match` | any hit from `iter()` | any match |
| first element of `find_iter` | `find`, `MatchKind::Standard` | first hit of `iter()` | first match |
| first element of `find_leftmost_longest` | `find`, `MatchKind::LeftmostLongest` | | |
| `~ignore_case:true` | `ascii_case_insensitive(true)` | patterns and input lowered with `bytes.lower()` | same |

The cases are the fixed vectors of `test/test_conformance.ml` (ported from
the Rust crate's own test tables, daachorse's additions, pyahocorasick's
`iter_long` regression tests and this library's documentation) followed
by generated ones: small alphabets (`ab`, `abc`, `abcd`, five byte
values including NUL and bytes above 0x7f, mixed-case letters, English
words), one to eight patterns of one to twelve bytes with deliberate
duplicates and substrings of each other, inputs up to 300 bytes with
patterns planted in them, and random chunk boundaries for the streamed
modes. Small alphabets are the point: they make patterns that are
suffixes and overlaps of one another dense, which is where
implementations disagree if they are going to.

## Results

Seed 20260904, 20 000 generated cases plus the fixed vectors: 20 348
cases.

| oracle | modes compared | cases with identical results |
|---|---|---|
| Rust `aho-corasick` 1.1.5 | 11 (every row above) | 20 348 of 20 348, in every mode |
| ahocorasick_rs 1.0.3 | 7 | 20 348 of 20 348, in every mode |
| pyahocorasick 2.3.1, `iter()` | overlapping, streamed overlapping, `mem`, first match | 20 348 of 20 348, in every mode, including the report order |
| pyahocorasick 2.3.1, `iter_long()` | leftmost-longest, whole and streamed | 19 685 of 20 348 |

So, on these cases, this library's overlapping search reports the same
matches in the same order as the Rust crate's `find_overlapping_iter`
and pyahocorasick's `iter()`; `Stream.feed_nonoverlapping` is exactly the
Rust crate's `find_iter` and `stream_find_iter` under standard
semantics; and `find_leftmost_longest`, `replace_all` and their streamed
forms are exactly the Rust crate's leftmost-longest search and
`replace_all`.

### pyahocorasick's `iter_long` is not leftmost-longest

The 663 cases where `iter_long()` differs from leftmost-longest are all
matches it fails to report. In 659 of them its output is the
leftmost-longest output with matches missing; in the other 4 a missed
match is followed by the selection of a later match that overlaps the
missed one. It never reports a match that is not an occurrence, and its
documented examples all agree with leftmost-longest, which is why the
documentation of both libraries reads as if the two coincide. Two
mechanisms account for every case:

- At end of input the failure chain is not consulted. Patterns `abc` and
  `b`, input `ab`: `b` at 1..2 is not reported; with input `ab ` it is.
- On a mismatch, only the immediate failure node is checked for a
  pattern. Patterns `abcd`, `bcx`, `c`, input `abcz`: `c` at 2..3 is
  not reported.

Both reproduce with pyahocorasick 2.3.1 from PyPI:

```python
import ahocorasick
def iter_long(patterns, text):
    a = ahocorasick.Automaton()
    for p in patterns: a.add_word(p, p)
    a.make_automaton()
    return list(a.iter_long(text))
iter_long(["abc", "b"], "ab")            # [] -- expected [(1, 'b')]
iter_long(["abcd", "bcx", "c"], "abcz")  # [] -- expected [(2, 'c')]
```

Upstream has fixed one such gap before ([#133](https://github.com/WojciechMula/pyahocorasick/issues/133),
fixed by [#174](https://github.com/WojciechMula/pyahocorasick/pull/174), regression noted in
[#185](https://github.com/WojciechMula/pyahocorasick/issues/185)) and has an open report about
`iter_long` ([#189](https://github.com/WojciechMula/pyahocorasick/issues/189)). The two
reproducers above are not in that tracker as of September 2026. The
comparison therefore runs with `--soft`: disagreements in these two modes
are counted and printed but do not fail the run. Every other mode is
strict.

## Running it

```sh
opam exec -- ./compat/run.sh                # 20 000 cases, seed 20260904
COUNT=100000 SEED=7 opam exec -- ./compat/run.sh
```

Requirements: dune (the harness builds `compat/ocaml/driver.exe` from
this repository), cargo (the Rust driver pins `aho-corasick` in its
`Cargo.lock`), and Python 3 with `pip install pyahocorasick==2.3.1`;
`ahocorasick_rs` is used when importable. Outputs land in `compat/_out/`:
`cases.tsv` and one `<driver>.tsv` per implementation. A disagreement is
printed with the case decoded, so it can be pasted straight into an
issue.

Anything else can be plugged in by writing a driver that speaks the
formats below and adding a `compare.py` line to `run.sh`.

## Formats

`cases.tsv`: one case per line, five tab-separated fields.

| field | content |
|---|---|
| id | integer |
| flags | `-`, or `i` for ASCII case-insensitive matching |
| patterns | comma-separated, each hex-encoded; empty for no patterns |
| input | hex-encoded |
| chunks | comma-separated chunk sizes for the streamed modes; whatever remains after them is the final chunk |

Results: one line per case and mode, three tab-separated fields: id,
mode, result. A match list is `pattern:start:stop` triples separated by
spaces, or `-` when empty; `replace` results are hex-encoded; `is_match`
is `true` or `false`.

`compare.py` compares the subject's result to the oracle's for every
(id, mode) both report, with `--map SUBJECT_MODE=ORACLE_MODE` for modes
named differently, and classifies a match-list difference as "same set,
different order" when only the order differs.

## How other projects do this

The layout follows what the implementations compared here do themselves.
The Rust crate keeps table-driven vectors per match kind and runs every
table against every engine it has (`src/tests.rs`); its
[rebar](https://github.com/BurntSushi/rebar) benchmark definitions carry
an expected match count that each engine must reproduce, which makes the
benchmark a cross-engine check as well (`bench/` here does the same).
[daachorse](https://github.com/daac-tools/daachorse) copies the crate's
vector tables verbatim into its own suite, as `test/test_conformance.ml`
does. [ahocorasick_rs](https://github.com/G-Research/ahocorasick_rs)
property-tests against a naive scan and benchmarks pyahocorasick on the
same data. None of them, as far as we found, runs a generated
differential test across independent implementations; that is what this
directory adds.
