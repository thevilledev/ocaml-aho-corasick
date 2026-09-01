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
