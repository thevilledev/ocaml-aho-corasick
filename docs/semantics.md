# Match rules and performance

[Back to README](../README.md) · [Streaming examples](usage.md#choose-a-streaming-mode)

## Offsets and patterns

A match `{ pattern; start; stop }` covers bytes `[start, stop)`.
Its length is `stop - start`; extract it with
`String.sub text start (stop - start)`. Pattern IDs are zero-based indices
in the list passed to `build`.

- Patterns are literal byte strings. NUL and all other byte values work.
- UTF-8 is matched byte for byte; offsets are not character indices.
- `~ignore_case:true` folds only ASCII `A`–`Z`. It does not normalize Unicode.
- An empty pattern list matches nothing. An empty pattern string raises
  `Invalid_argument`.
- Duplicate patterns report separate IDs. This also applies to different
  spellings that become equal after ASCII folding.

## Overlapping search

`find_all`, `find_iter`, and `Stream.feed` report every occurrence, ordered by:

1. Increasing `stop`.
2. Decreasing match length for the same `stop`.
3. Increasing pattern ID for identical spans.

For `["he"; "she"; "his"; "hers"]` in `"ushers"`, the result is
`she@1..4`, `he@2..4`, `hers@2..6`.

## Non-overlapping selection

**Earliest end** (`Stream.feed_nonoverlapping`): take the first match to
finish, choosing the longest match at that end position and then the
lowest pattern ID. Restart immediately after that match.

**Leftmost-longest** (`find_leftmost_longest`, `replace_all`,
`Stream.Leftmost_longest`, `Stream.Replace`): choose the smallest start
position, then the greatest length, then the lowest pattern ID. Continue
after the selected match, discarding overlaps.

| Patterns | Input | Overlapping | Earliest end | Leftmost-longest |
| --- | --- | --- | --- | --- |
| `Samwise`, `Sam` | `Samwise` | `Sam@0..3`, `Samwise@0..7` | `Sam@0..3` | `Samwise@0..7` |
| `abcd`, `b` | `abcd` | `b@1..2`, `abcd@0..4` | `b@1..2` | `abcd@0..4` |
| `aa` | `aaaa` | `aa@0..2`, `aa@1..3`, `aa@2..4` | `aa@0..2`, `aa@2..4` | `aa@0..2`, `aa@2..4` |

There is no leftmost-first mode that gives an earlier pattern priority over
a longer one.

## Streaming state

Use a state only with the automaton that created it. Keep the returned
state and use one mode throughout. States are immutable; retaining an old
state lets you branch a scan. Total byte offsets must fit in an OCaml `int`.

`Stream.feed` and `feed_nonoverlapping` do not retain input bytes or need
an end-of-input call. Leftmost-longest modes wait until no earlier or
longer match can appear, using a lookahead window of at most the longest
pattern length. Finish with `flush`, consume its result once, and do not
feed that state again. Replacement callbacks should be deterministic if
you compare output across chunk splits or replay states.

## Performance

Let `n` be input length, `m` the number of matching patterns examined,
`r` the number of selected matches, and `L` the longest pattern length.

| Operation | Time | Extra storage, excluding automaton and returned output |
| --- | --- | --- |
| `find_all` | O(n + m) | O(m) to collect matches |
| `find_iter` | O(n + m) when exhausted | Matches at the current end position |
| `mem` | O(n), stops on first match | O(1) |
| `find_leftmost_longest` | O(n + m) | O(L + r) |
| `replace_all` | O(n + m), plus replacement output | O(L + r) |
| `Stream.feed` | O(chunk length + matches in chunk) | Matches in chunk |
| `Stream.feed_nonoverlapping` | O(chunk length) | Selected matches in chunk |
| `Stream.Leftmost_longest.feed` | O(chunk length + matches examined) | O(L), plus selected matches returned |
| `Stream.Replace.feed` | O(chunk length + matches examined), plus output | O(L), plus returned output |

Leftmost-longest matching keeps the best match for each possible start in a
ring of `L + 1` slots. It selects a start when no longer match can reach it,
without collecting or sorting all overlapping matches. The streamed form
retains at most `L` candidates. `Stream.Replace` additionally retains at
most `L` input bytes.

The automaton stores a trie, failure links, dictionary-suffix links, and
resolved 256-entry transition rows for up to the first 4,096 nodes.
Deeper nodes use sorted child arrays. Storage grows with total pattern
length; there is no SIMD prefilter. See the [benchmark method and
results](../bench/README.md).

## Porting from Rust

Rust's `find_iter` is non-overlapping. This library's `find_iter` is the
counterpart of Rust's `find_overlapping_iter`. Rust's
`MatchKind::LeftmostLongest` corresponds to this library's leftmost-longest
selection for non-empty byte patterns.

Rust's `stream_find_iter` uses `MatchKind::Standard` and earliest-end
selection. This library specifies its own same-end tie-breaking above;
Rust 1.1.5 only allows standard match semantics for streaming, while this
library also provides the two leftmost-longest streaming modules.

The conformance suite ports vectors from Rust `aho-corasick`, daachorse, and
pyahocorasick. A differential harness compares 20,000 generated cases with
Rust `aho-corasick` 1.1.5, pyahocorasick 2.3.1, and ahocorasick_rs 1.0.3.
All shared Rust modes matched, including order; scope and known Python
differences are recorded in [compat/README.md](../compat/README.md).
