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
  (sockets, files), with absolute offsets
- `?ignore_case` — ASCII case folding

Correctness is anchored by a QCheck oracle: `find_all` is compared
against a naive per-pattern scan across thousands of random
pattern-set/input combinations, and streaming across random chunk splits
must equal whole-input scanning.

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
```

Build the automaton once and reuse it: `t` is immutable and safe to
share across threads.

## Notes

- Matching is byte-oriented; UTF-8 input works as byte matching
  (`?ignore_case` folds ASCII letters only).
- Construction is O(total pattern length); matching is
  O(input + number of matches) via failure and dictionary-suffix links.
- Match reporting order for `find_all`: by end offset; ties longest
  first.

## License

MIT — see [LICENSE](LICENSE).
