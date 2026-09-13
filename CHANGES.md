# Changelog

## 0.1.0 (2026-09-13)

Initial release.

### Added

- Immutable Aho-Corasick automata for literal byte-string patterns.
- Overlapping search (`find_all`), lazy iteration (`find_iter`), and
  early-exit membership (`mem`).
- Non-overlapping leftmost-longest search and callback-based replacement.
- Streaming across chunk boundaries with absolute byte offsets: overlapping,
  earliest-end non-overlapping, and leftmost-longest matching.
- Streamed replacement with lookahead bounded by the longest pattern.
- ASCII case-insensitive matching and duplicate pattern IDs.
- Usage, semantics, development, and release guides; a documentation website
  and generated API reference.
- Unit tests and independent QCheck oracles for match ordering, selection,
  replacement, and streaming equivalence, including binary inputs.
- Conformance vectors from Rust `aho-corasick`, daachorse, and pyahocorasick,
  plus a differential harness covering 20,000 generated cases.
- Reproducible, count-checked benchmarks over text corpora and synthetic
  dense, sparse, and pathological inputs.
- Dense transition rows for shallow nodes, sorted child arrays for deeper
  nodes, allocation-free scanning between matches, and single-pass
  leftmost-longest selection.

### Release preparation

- Specify tie-breaking, stream lifecycle, and memory/performance costs.
- Align generated opam metadata, test dependency bounds, installed docs,
  and CI checks with the v0.1.0 package.

Requires OCaml >= 4.14 and Dune >= 3.17.2. Licensed under MIT.
