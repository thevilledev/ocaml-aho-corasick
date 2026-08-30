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
    offsets are absolute across everything fed so far. *)
module Stream : sig
  type state
  (** Immutable scanning position; keep the value returned by {!feed}. *)

  val start : t -> state

  val feed : t -> state -> string -> state * match_ list
  (** [feed t st chunk] scans [chunk], returning the advanced state and
      the matches whose last byte lies in [chunk] (offsets are
      absolute). There is nothing to flush: every match is reported as
      soon as its final byte is seen. *)

  val pos : state -> int
  (** Total bytes fed so far. *)
end
