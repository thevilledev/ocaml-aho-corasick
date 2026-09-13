# Usage

[Back to README](../README.md) · [Match rules](semantics.md) ·
[API reference](https://ville.dev/ocaml-aho-corasick/api/aho-corasick/Aho_corasick/index.html)

## Find and inspect matches

```ocaml
let matcher = Aho_corasick.build [ "he"; "she"; "his"; "hers" ]
let matches = Aho_corasick.find_all matcher "ushers"
let names =
  List.map
    (fun (m : Aho_corasick.match_) -> Aho_corasick.pattern matcher m.pattern)
    matches
(* ["she"; "he"; "hers"] *)
```

`pattern_count` includes duplicates. `pattern matcher i` returns the
original spelling, even when the matcher was built with `~ignore_case:true`.

Use `mem matcher text` for a yes/no answer. Use `find_iter matcher text`
to consume overlapping matches lazily as a `Seq.t`; it stops scanning when
you stop consuming. Matches are ordered by end position, then longest
first, then by pattern index.

## Replace matches

```ocaml
let matcher = Aho_corasick.build [ "Sam"; "Samwise" ]
let output =
  Aho_corasick.replace_all matcher "Samwise and Sam"
    ~f:(fun m -> Printf.sprintf "[%d]" m.pattern)
(* "[1] and [0]" *)
```

Replacement uses leftmost-longest selection. A callback receives the
original input's match offsets. Its output is inserted literally and is
not searched again. Return `""` to delete a match.

## Choose a streaming mode

With patterns `["Samwise"; "Sam"]` and input `"Samwise"`:

| Mode | Reports | API | End of input |
| --- | --- | --- | --- |
| Overlapping | `Sam`, `Samwise` | `Stream.feed` | Nothing to flush |
| Earliest end, non-overlapping | `Sam` | `Stream.feed_nonoverlapping` | Nothing to flush |
| Leftmost-longest | `Samwise` | `Stream.Leftmost_longest` | Call `flush` |
| Replace leftmost-longest | Callback output for `Samwise` | `Stream.Replace` | Append `flush` output |

All modes accept empty chunks and return absolute byte offsets. Pass the
same automaton on every call and keep the returned state. Use `feed` or
`feed_nonoverlapping` consistently for a stream; do not mix them.

### Overlapping matches across chunks

```ocaml
let matcher = Aho_corasick.build [ "he"; "she"; "his"; "hers" ]
let state = Aho_corasick.Stream.start matcher
let state, first = Aho_corasick.Stream.feed matcher state "ush"
let state, second = Aho_corasick.Stream.feed matcher state "ers"
(* first = []; second: she 1..4, he 2..4, hers 2..6 *)
let bytes_seen = Aho_corasick.Stream.pos state
(* 6 *)
```

For earliest-end non-overlapping matches, use `feed_nonoverlapping` with
the same call shape. A match is reported in the call that sees its final byte.

### Leftmost-longest matches

```ocaml
module L = Aho_corasick.Stream.Leftmost_longest
let matcher = Aho_corasick.build [ "Sam"; "Samwise" ]
let state = L.start matcher
let state, first = L.feed matcher state "Sam"
let state, second = L.feed matcher state "wise Sam"
let last = L.flush state
let matches = first @ second @ last
(* Samwise 0..7, Sam 8..11 *)
```

A short match can be held back while a longer one could still arrive.
Lookahead is bounded by the longest pattern. Call `flush` once at end of
input, including when the last chunk is empty; do not feed the finished
state again.

### Streamed replacement

```ocaml
module R = Aho_corasick.Stream.Replace
let matcher = Aho_corasick.build [ "Sam"; "Samwise" ]
let state = R.start matcher ~f:(fun _ -> "[name]")
let state, first = R.feed matcher state "Sam"
let state, second = R.feed matcher state "wise and Sam"
let output = first ^ second ^ R.flush state
(* "[name] and [name]" *)
```

For a file or socket, write each returned piece to the destination as it
arrives, then write `flush`'s final piece. Keep only the latest state.
Repeated string concatenation in a long loop copies the accumulated
output; use an output channel or `Buffer` instead.

Replacement retains at most one longest-pattern window of input.
Leftmost-longest matching retains at most one candidate per possible start
in that window and does not collect every overlapping match. See the
[performance notes](semantics.md#performance) for dense pattern sets.
