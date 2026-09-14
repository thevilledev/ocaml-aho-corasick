# ocaml-aho-corasick

[![CI](https://github.com/thevilledev/ocaml-aho-corasick/actions/workflows/ci.yml/badge.svg)](https://github.com/thevilledev/ocaml-aho-corasick/actions/workflows/ci.yml)

Find many literal patterns in one pass over a byte string. Pure OCaml,
with no runtime dependencies beyond the standard library.

Supports overlapping matches, lazy iteration, leftmost-longest selection,
replacement, ASCII case folding, and streaming across chunk boundaries.

## Install

Requires OCaml 4.14 or newer and Dune 3.14 or newer.

Until v0.1.1 is published to opam, install from this checkout:

```sh
opam install .
```

After publication:

```sh
opam install aho-corasick
```

Add `(libraries aho-corasick)` to your executable or library's Dune stanza.

## Quick start

```ocaml
let matcher = Aho_corasick.build [ "he"; "she"; "his"; "hers" ]
let matches = Aho_corasick.find_all matcher "ushers"
(* she: 1..4, he: 2..4, hers: 2..6 *)

let words = Aho_corasick.build [ "cat"; "dog" ]
let replaced =
  Aho_corasick.replace_all words ~f:(fun _ -> "[pet]") "cat and dog"
(* "[pet] and [pet]" *)
```

Each match has a `pattern` index into the original pattern list, a `start`
byte offset, and an exclusive `stop` byte offset. Build once and reuse the
immutable matcher.

`find_all` and `find_iter` include overlaps. `find_leftmost_longest` and
`replace_all` choose non-overlapping matches, preferring the longest match
at the earliest position. `mem` stops at the first match.

Matching uses bytes, including for UTF-8. `~ignore_case:true` folds ASCII
letters only. Empty pattern lists are allowed; empty strings as patterns
raise `Invalid_argument`.

## Documentation

- [Usage and streaming examples](docs/usage.md)
- [Match rules and performance](docs/semantics.md)
- [Compatibility and differential testing](compat/README.md)
- [Reproducible benchmarks](bench/README.md) and
  [published results](https://ville.dev/ocaml-aho-corasick/performance.html)
- [Building and testing](docs/development.md)
- [Release procedure](docs/releasing.md) and [changelog](CHANGES.md)
- [Website](https://ville.dev/ocaml-aho-corasick/) and
  [API reference](https://ville.dev/ocaml-aho-corasick/api/aho-corasick/Aho_corasick/index.html)

## License

[MIT](LICENSE).
