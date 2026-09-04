# 0.1.0 (unreleased)

- Initial release.
- Aho-Corasick automaton with overlapping search, lazy iteration,
  leftmost-longest selection, replacement, early-exit membership and
  chunked streaming.
- Streaming in three semantics: every match (`Stream.feed`),
  non-overlapping earliest-end (`Stream.feed_nonoverlapping`, the
  semantics of Rust aho-corasick's `stream_find_iter`), and
  leftmost-longest with lookahead bounded by the longest pattern
  (`Stream.Leftmost_longest`) — plus streamed replacement
  (`Stream.Replace`).
- QCheck oracle tests against a naive reference scan, and each
  streaming mode against its whole-input counterpart across random
  chunk splits.
- Conformance tests ported from the Rust `aho-corasick` crate's test
  tables (plus daachorse's and pyahocorasick's vectors and the crate's
  documentation examples), run through every function with matching
  semantics, whole-input and streamed.
- A differential harness (`compat/`) that runs the library, the Rust
  crate, pyahocorasick and ahocorasick_rs over 20 000 generated cases
  and compares the outputs; it runs in CI. Results: identical to the
  Rust crate in every mode; pyahocorasick's `iter_long` misses matches
  (documented in `compat/README.md`).
- Benchmarks (`bench/`) over rebar's corpora and synthetic inputs,
  comparing the same implementations and cross-checking match counts.
- Faster scanning: the shallowest nodes carry fully resolved 256-entry
  transition rows and deeper nodes sorted child arrays, replacing the
  hash table; match reporting no longer allocates per byte; streamed
  leftmost-longest selection is a single pass over its candidates.
- Documentation site updated for the streaming modes, the differential
  test and the benchmarks.
