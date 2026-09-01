(** Aho–Corasick multi-pattern string matching.

    Build an automaton from a set of patterns once, then find every
    occurrence of every pattern in an input with a single left-to-right
    pass: O(input + matches), independent of how many patterns there
    are. This is the standard algorithm behind secret scanners, WAF and
    IDS signature matching, log filtering and dictionary tagging.

    Matching is byte-oriented and 8-bit clean: patterns and inputs are
    arbitrary [string]s (UTF-8 works as byte matching; [?ignore_case]
    folds ASCII letters only).

    Reference: Aho & Corasick, "Efficient string matching: an aid to
    bibliographic search", CACM 18(6), 1975. *)

type t
(** A compiled automaton. Immutable and safe to share across threads. *)

type match_ = {
  pattern : int;  (** Index of the pattern in the list given to {!build}. *)
  start : int;  (** Byte offset of the first matched byte. *)
  stop : int;  (** Byte offset one past the last matched byte. *)
}

val build : ?ignore_case:bool -> string list -> t
(** [build patterns] compiles the automaton. Duplicate patterns are
    allowed (each occurrence reports every duplicate's index). With
    [~ignore_case:true], ASCII letters match case-insensitively.
    An empty pattern list yields an automaton that matches nothing.

    @raise Invalid_argument if any pattern is the empty string. *)

val pattern_count : t -> int

val pattern : t -> int -> string
(** The original pattern for a {!match_}'s [pattern] index.

    @raise Invalid_argument if the index is out of bounds. *)

(** {1 Searching} *)

val find_all : t -> string -> match_ list
(** Every match of every pattern, including overlapping ones. Ordered
    by [stop]; matches ending at the same position come longest first. *)

val find_iter : t -> string -> match_ Seq.t
(** Like {!find_all}, but lazily — stop consuming to stop scanning. *)

val find_leftmost_longest : t -> string -> match_ list
(** Non-overlapping matches, chosen greedily: repeatedly take the match
    with the smallest [start] (breaking ties by greatest length), then
    discard everything overlapping it. This is the "replace" semantics
    of POSIX tools. *)

val mem : t -> string -> bool
(** Does any pattern occur? Scans only as far as the first match. *)

val replace_all : t -> f:(match_ -> string) -> string -> string
(** Replace each {!find_leftmost_longest} match [m] with [f m]. *)

(** {1 Streaming}

    Scan input arriving in chunks (sockets, files) without
    concatenating: matches spanning chunk boundaries are found, and
    offsets are absolute across everything fed so far.

    Three semantics mirror the whole-input searches:

    - {!val:Stream.feed} reports every match, overlapping included —
      {!find_all}, chunked.
    - {!val:Stream.feed_nonoverlapping} reports non-overlapping matches
      with no buffering or latency, the semantics of Rust aho-corasick's
      [stream_find_iter].
    - {!module:Stream.Leftmost_longest} and {!module:Stream.Replace}
      stream the {!find_leftmost_longest} / {!replace_all} selection,
      using lookahead bounded by the longest pattern. *)
module Stream : sig
  type state
  (** Immutable scanning position; keep the value returned by {!feed}. *)

  val start : t -> state

  val feed : t -> state -> string -> state * match_ list
  (** [feed t st chunk] scans [chunk], returning the advanced state and
      the matches whose last byte lies in [chunk] (offsets are
      absolute). Every match is reported, overlapping ones included, as
      soon as its final byte is seen; there is never anything to
      flush. *)

  val feed_nonoverlapping : t -> state -> string -> state * match_ list
  (** Like {!feed}, but non-overlapping, preferring the match that ends
      first: whenever one or more matches end, the longest of them is
      reported and scanning restarts immediately after it, so no later
      match overlaps it. Zero latency and nothing to flush, like
      {!feed}. These are the semantics of Rust aho-corasick's
      [stream_find_iter] ([MatchKind::Standard]): with patterns
      [["Samwise"; "Sam"]] and input ["Samwise"], the one match is
      [Sam].

      Feed any given stream exclusively with [feed] or exclusively with
      [feed_nonoverlapping]: both advance the same state type, but the
      restart-after-match discipline only makes sense applied to the
      whole stream. *)

  val pos : state -> int
  (** Total bytes fed so far. *)

  (** Non-overlapping leftmost-longest matches — the
      {!find_leftmost_longest} selection, streamed.

      This selection needs lookahead: a match may only be reported once
      no longer match starting at or before it can still arrive.
      Because no match exceeds the longest pattern, that lookahead is
      bounded: a match is reported by the first {!Leftmost_longest.feed}
      whose input reaches one longest-pattern length past the match's
      start, and the state buffers at most that window of candidates.
      Call {!Leftmost_longest.flush} at end of input for the rest.

      (Rust's aho-corasick rejects leftmost match kinds on streams;
      this module is how a stream is redacted or tokenized with POSIX
      "replace" semantics without concatenating it first.) *)
  module Leftmost_longest : sig
    type state

    val start : t -> state

    val feed : t -> state -> string -> state * match_ list
    (** The matches selected so far, in order, with absolute offsets. *)

    val flush : state -> match_ list
    (** The remaining matches at end of input. The stream is finished:
        do not [feed] the state again. *)

    val pos : state -> int
    (** Total bytes fed so far. *)
  end

  (** {!replace_all}, streamed: each {!Leftmost_longest} match [m] is
      replaced by [f m], everything else passes through unchanged.

      [feed] returns the next piece of the output; input is held back
      only while it could still belong to a match (at most one
      longest-pattern length), so pieces flow promptly.
      {!Replace.flush} returns the final piece: the concatenation of
      all pieces equals [replace_all ~f] of the concatenated input. *)
  module Replace : sig
    type state

    val start : t -> f:(match_ -> string) -> state

    val feed : t -> state -> string -> state * string

    val flush : state -> string
    (** The stream is finished: do not [feed] the state again. *)

    val pos : state -> int
    (** Total bytes fed so far. *)
  end
end
