# ocaml-aho-corasick

[![CI](https://github.com/thevilledev/ocaml-aho-corasick/actions/workflows/ci.yml/badge.svg)](https://github.com/thevilledev/ocaml-aho-corasick/actions/workflows/ci.yml)

[Aho–Corasick](https://dl.acm.org/doi/10.1145/360825.360855) multi-pattern
string matching for OCaml: search for *many* patterns in *one* pass over
the input, in time linear in the input size — independent of how many
patterns you have.

This is the workhorse algorithm behind secret scanners, WAF/IDS
signature matching, log filtering, profanity filters and dictionary
tagging. Pure OCaml, zero dependencies.

- `find_all` — every match, including overlapping ones
- `find_iter` — the same, lazily
- `find_leftmost_longest` — non-overlapping, POSIX-tool "replace"
  semantics; drives `replace_all`
- `mem` — early-exit "does anything match?"
- `Stream` — chunked scanning with matches across chunk boundaries
  (sockets, files), with absolute offsets, in your choice of semantics:
  every match (`feed`), non-overlapping (`feed_nonoverlapping`),
  leftmost-longest (`Stream.Leftmost_longest`) — plus streamed
  replacement (`Stream.Replace`)
- `?ignore_case` — ASCII case folding

Correctness is anchored by QCheck oracles: `find_all` is compared
against a naive per-pattern scan across thousands of random
pattern-set/input combinations, and each streaming mode across random
chunk splits must equal its whole-input counterpart.

## Documentation

Match semantics, how they line up with other Aho-Corasick implementations,
and how correctness is checked:
[ville.dev/ocaml-aho-corasick](https://ville.dev/ocaml-aho-corasick/).
The generated API reference lives at
[ville.dev/ocaml-aho-corasick/api](https://ville.dev/ocaml-aho-corasick/api/).

## Install

```sh
opam install aho-corasick   # once released
opam pin add aho-corasick https://github.com/thevilledev/ocaml-aho-corasick.git
```

## Usage

```ocaml
let t = Aho_corasick.build [ "he"; "she"; "his"; "hers" ] in

Aho_corasick.find_all t "ushers"
(* [{pattern = 1; start = 1; stop = 4};   she
    {pattern = 0; start = 2; stop = 4};   he
    {pattern = 3; start = 2; stop = 6}]   hers *)

(* Redact a dictionary of secrets from a log line *)
let scrub = Aho_corasick.replace_all t ~f:(fun _ -> "[REDACTED]")

(* Scan a stream without concatenating chunks *)
let st = Aho_corasick.Stream.start t in
let st, matches = Aho_corasick.Stream.feed t st chunk1 in
let _st, more = Aho_corasick.Stream.feed t st chunk2 in
(* matches spanning the chunk1/chunk2 boundary are found, with
   absolute offsets *)

(* Redact a stream with replace_all's semantics, without concatenating:
   input is held back only while it could still belong to a match *)
let module R = Aho_corasick.Stream.Replace in
let st = R.start t ~f:(fun _ -> "[REDACTED]") in
let st, out1 = R.feed t st chunk1 in
let st, out2 = R.feed t st chunk2 in
let out3 = R.flush st in
(* out1 ^ out2 ^ out3 = replace_all of the whole input *)
```

Build the automaton once and reuse it: `t` is immutable and safe to
share across threads.

## Match semantics

With patterns `["Samwise"; "Sam"]` on `"Samwise"`, three different
answers are all reasonable, so all three are offered — over whole
inputs and over streams:

| semantics                          | reports          | whole input                             | stream                                      |
| ---------------------------------- | ---------------- | --------------------------------------- | ------------------------------------------- |
| overlapping (every match)          | `Sam`, `Samwise` | `find_all`, `find_iter`                 | `Stream.feed`                               |
| non-overlapping, earliest end wins | `Sam`            | —                                       | `Stream.feed_nonoverlapping`                |
| non-overlapping, leftmost-longest  | `Samwise`        | `find_leftmost_longest`, `replace_all`  | `Stream.Leftmost_longest`, `Stream.Replace` |

The first two stream modes report a match the moment its last byte is
seen and never buffer. Leftmost-longest inherently needs lookahead (a
longer match may still be forming), but no match can outgrow the
longest pattern, so `Stream.Leftmost_longest` and `Stream.Replace`
buffer at most one longest-pattern window and are exact: fed any chunk
split of an input, they produce precisely what their whole-input
counterparts produce, with a final `flush` for what remains.

### Relative to Rust's aho-corasick

For anyone arriving from Rust's
[aho-corasick](https://docs.rs/aho-corasick): the names do not line up
one-to-one, and the streaming APIs differ in what they can express.

- Rust's `find_iter` is non-overlapping; this library's `find_iter` is
  the lazy form of `find_all` and reports overlapping matches (Rust's
  `find_overlapping_iter`). For non-overlapping selection use
  `find_leftmost_longest` (Rust's `MatchKind::LeftmostLongest`).
- Rust's stream iterator is non-overlapping, unlike this library's
  default: `stream_find_iter` supports only `MatchKind::Standard`, and
  leftmost match kinds are rejected on streams. Here a stream can be
  scanned any of the three ways: `Stream.feed` reports every
  overlapping match (which Rust's streams cannot), `feed_nonoverlapping`
  matches `stream_find_iter`'s semantics exactly, and
  `Stream.Leftmost_longest` / `Stream.Replace` bring leftmost-longest —
  and `replace_all` — to streams, which Rust's streams cannot do at
  all.

## Notes

- Matching is byte-oriented; UTF-8 input works as byte matching
  (`?ignore_case` folds ASCII letters only).
- Construction is O(total pattern length); matching is
  O(input + number of matches) via failure and dictionary-suffix links.
- Match reporting order for `find_all`: by end offset; ties longest
  first.

## License

MIT — see [LICENSE](LICENSE).
