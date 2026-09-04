(* Conformance vectors ported from other Aho-Corasick implementations.

   Every vector is (patterns, input, expected matches), with matches as
   (pattern index, start, stop) in half-open byte offsets, in the order
   the source implementation reports them. Each vector is run through
   every function here that promises the same semantics, whole-input and
   streamed, so agreement with the source is checked on all of them.

   Sources:

   - BurntSushi/aho-corasick 1.1.5, src/tests.rs (Unlicense OR MIT):
     the BASICS, STANDARD, NON_OVERLAPPING, OVERLAPPING, LEFTMOST,
     LEFTMOST_LONGEST, ASCII_CASE_INSENSITIVE and REGRESSION tables, and
     the standalone regression tests, plus the examples in its API
     documentation. The LEFTMOST_FIRST and anchored tables are not
     ported: neither semantics exists here. Vectors that contain the
     empty pattern are not ported either: [build] rejects it.
   - daac-tools/daachorse, tests/aho_corasick_crate_test.rs
     (MIT OR Apache-2.0): the vectors it adds to the same tables.
   - WojciechMula/pyahocorasick, docs/automaton_iter_long.rst and
     tests/test_issue_133.py (BSD-3-Clause): iter_long vectors, checked
     here against find_leftmost_longest.
   - website/compatibility.html: the vectors this library documents.

   The differential harness under compat/ runs the same vectors, and
   thousands of generated ones, through the Rust and Python libraries
   themselves; this file is what makes the ported vectors part of the
   ordinary test suite. *)

open Aho_corasick

type vector = {
  name : string;
  patterns : string list;
  haystack : string;
  expected : (int * int * int) list;
}

let v name patterns haystack expected = { name; patterns; haystack; expected }

(* ---------- BurntSushi/aho-corasick src/tests.rs ---------- *)

(* BASICS: identical under every match kind, overlapping or not. *)
let basics =
  [
    v "basic000" [] "" [];
    v "basic002" [ "a" ] "" [];
    v "basic010" [ "a" ] "a" [ (0, 0, 1) ];
    v "basic020" [ "a" ] "aa" [ (0, 0, 1); (0, 1, 2) ];
    v "basic030" [ "a" ] "aaa" [ (0, 0, 1); (0, 1, 2); (0, 2, 3) ];
    v "basic040" [ "a" ] "aba" [ (0, 0, 1); (0, 2, 3) ];
    v "basic050" [ "a" ] "bba" [ (0, 2, 3) ];
    v "basic060" [ "a" ] "bbb" [];
    v "basic070" [ "a" ] "bababbbba" [ (0, 1, 2); (0, 3, 4); (0, 8, 9) ];
    v "basic100" [ "aa" ] "" [];
    v "basic110" [ "aa" ] "aa" [ (0, 0, 2) ];
    v "basic120" [ "aa" ] "aabbaa" [ (0, 0, 2); (0, 4, 6) ];
    v "basic130" [ "aa" ] "abbab" [];
    v "basic140" [ "aa" ] "abbabaa" [ (0, 5, 7) ];
    v "basic200" [ "abc" ] "abc" [ (0, 0, 3) ];
    v "basic210" [ "abc" ] "zazabzabcz" [ (0, 6, 9) ];
    v "basic220" [ "abc" ] "zazabczabcz" [ (0, 3, 6); (0, 7, 10) ];
    v "basic300" [ "a"; "b" ] "" [];
    v "basic310" [ "a"; "b" ] "z" [];
    v "basic320" [ "a"; "b" ] "b" [ (1, 0, 1) ];
    v "basic330" [ "a"; "b" ] "a" [ (0, 0, 1) ];
    v "basic340" [ "a"; "b" ] "abba" [ (0, 0, 1); (1, 1, 2); (1, 2, 3); (0, 3, 4) ];
    v "basic350" [ "b"; "a" ] "abba" [ (1, 0, 1); (0, 1, 2); (0, 2, 3); (1, 3, 4) ];
    v "basic360" [ "abc"; "bc" ] "xbc" [ (1, 1, 3) ];
    v "basic400" [ "foo"; "bar" ] "" [];
    v "basic410" [ "foo"; "bar" ] "foobar" [ (0, 0, 3); (1, 3, 6) ];
    v "basic420" [ "foo"; "bar" ] "barfoo" [ (1, 0, 3); (0, 3, 6) ];
    v "basic430" [ "foo"; "bar" ] "foofoo" [ (0, 0, 3); (0, 3, 6) ];
    v "basic440" [ "foo"; "bar" ] "barbar" [ (1, 0, 3); (1, 3, 6) ];
    v "basic450" [ "foo"; "bar" ] "bafofoo" [ (0, 4, 7) ];
    v "basic460" [ "bar"; "foo" ] "bafofoo" [ (1, 4, 7) ];
    v "basic470" [ "foo"; "bar" ] "fobabar" [ (1, 4, 7) ];
    v "basic480" [ "bar"; "foo" ] "fobabar" [ (0, 4, 7) ];
    v "basic700" [ "yabcdef"; "abcdezghi" ] "yabcdefghi" [ (0, 0, 7) ];
    v "basic710" [ "yabcdef"; "abcdezghi" ] "yabcdezghi" [ (1, 1, 10) ];
    v "basic720" [ "yabcdef"; "bcdeyabc"; "abcdezghi" ] "yabcdezghi" [ (2, 1, 10) ];
    (* daachorse additions *)
    v "basic_daachorse001" [] "a" [];
    v "basic_daachorse002" [] "abc" [];
  ]

(* STANDARD: non-overlapping, the match that ends first wins. *)
let standard =
  [
    v "standard000" [ "ab"; "abcd" ] "abcd" [ (0, 0, 2) ];
    v "standard010" [ "abcd"; "ab" ] "abcd" [ (1, 0, 2) ];
    v "standard020" [ "abcd"; "ab"; "abc" ] "abcd" [ (1, 0, 2) ];
    v "standard030" [ "abcd"; "abc"; "ab" ] "abcd" [ (2, 0, 2) ];
    v "standard400" [ "abcd"; "bcd"; "cd"; "b" ] "abcd" [ (3, 1, 2); (2, 2, 4) ];
  ]

(* NON_OVERLAPPING: identical under standard and leftmost kinds. *)
let non_overlapping =
  [
    v "nover010" [ "abcd"; "bcd"; "cd" ] "abcd" [ (0, 0, 4) ];
    v "nover020" [ "bcd"; "cd"; "abcd" ] "abcd" [ (2, 0, 4) ];
    v "nover030" [ "abc"; "bc" ] "zazabcz" [ (0, 3, 6) ];
    v "nover100" [ "ab"; "ba" ] "abababa" [ (0, 0, 2); (0, 2, 4); (0, 4, 6) ];
    v "nover200" [ "foo"; "foo" ] "foobarfoo" [ (0, 0, 3); (0, 6, 9) ];
    (* daachorse addition *)
    v "nover_daachorse001" [ "abc"; "abc" ] "abcabc" [ (0, 0, 3); (0, 3, 6) ];
  ]

(* OVERLAPPING: every match, in the order the Rust crate reports them,
   which is also the order specified here (end ascending, longest first,
   pattern index ascending). *)
let overlapping =
  [
    v "over000" [ "abcd"; "bcd"; "cd"; "b" ] "abcd"
      [ (3, 1, 2); (0, 0, 4); (1, 1, 4); (2, 2, 4) ];
    v "over010" [ "bcd"; "cd"; "b"; "abcd" ] "abcd"
      [ (2, 1, 2); (3, 0, 4); (0, 1, 4); (1, 2, 4) ];
    v "over020" [ "abcd"; "bcd"; "cd" ] "abcd" [ (0, 0, 4); (1, 1, 4); (2, 2, 4) ];
    v "over030" [ "bcd"; "abcd"; "cd" ] "abcd" [ (1, 0, 4); (0, 1, 4); (2, 2, 4) ];
    v "over040" [ "bcd"; "cd"; "abcd" ] "abcd" [ (2, 0, 4); (0, 1, 4); (1, 2, 4) ];
    v "over050" [ "abc"; "bc" ] "zazabcz" [ (0, 3, 6); (1, 4, 6) ];
    v "over100" [ "ab"; "ba" ] "abababa"
      [ (0, 0, 2); (1, 1, 3); (0, 2, 4); (1, 3, 5); (0, 4, 6); (1, 5, 7) ];
    v "over200" [ "foo"; "foo" ] "foobarfoo"
      [ (0, 0, 3); (1, 0, 3); (0, 6, 9); (1, 6, 9) ];
    v "over360" [ "foo"; "foofoo" ] "foofoo" [ (0, 0, 3); (1, 0, 6); (0, 3, 6) ];
  ]

(* LEFTMOST: identical under leftmost-first and leftmost-longest. *)
let leftmost =
  [
    v "leftmost000" [ "ab"; "ab" ] "abcd" [ (0, 0, 2) ];
    v "leftmost030" [ "a"; "ab" ] "aa" [ (0, 0, 1); (0, 1, 2) ];
    v "leftmost031" [ "ab"; "a" ] "aa" [ (1, 0, 1); (1, 1, 2) ];
    v "leftmost032" [ "ab"; "a" ] "xayabbbz" [ (1, 1, 2); (0, 3, 5) ];
    v "leftmost300" [ "abcd"; "bce"; "b" ] "abce" [ (1, 1, 4) ];
    v "leftmost310" [ "abcd"; "ce"; "bc" ] "abce" [ (2, 1, 3) ];
    v "leftmost320" [ "abcd"; "bce"; "ce"; "b" ] "abce" [ (1, 1, 4) ];
    v "leftmost330" [ "abcd"; "bce"; "cz"; "bc" ] "abcz" [ (3, 1, 3) ];
    v "leftmost340" [ "bce"; "cz"; "bc" ] "bcz" [ (2, 0, 2) ];
    v "leftmost350" [ "abc"; "bd"; "ab" ] "abd" [ (2, 0, 2) ];
    v "leftmost360" [ "abcdefghi"; "hz"; "abcdefgh" ] "abcdefghz" [ (2, 0, 8) ];
    v "leftmost370" [ "abcdefghi"; "cde"; "hz"; "abcdefgh" ] "abcdefghz" [ (3, 0, 8) ];
    v "leftmost380" [ "abcdefghi"; "hz"; "abcdefgh"; "a" ] "abcdefghz" [ (2, 0, 8) ];
    v "leftmost390" [ "b"; "abcdefghi"; "hz"; "abcdefgh" ] "abcdefghz" [ (3, 0, 8) ];
    v "leftmost400" [ "h"; "abcdefghi"; "hz"; "abcdefgh" ] "abcdefghz" [ (3, 0, 8) ];
    v "leftmost410" [ "z"; "abcdefghi"; "hz"; "abcdefgh" ] "abcdefghz"
      [ (3, 0, 8); (0, 8, 9) ];
    (* daachorse addition *)
    v "leftmost_daachorse003" [ "a"; "a" ] "abab" [ (0, 0, 1); (0, 2, 3) ];
  ]

(* LEFTMOST_LONGEST: specific to leftmost-longest. *)
let leftmost_longest =
  [
    v "leftlong000" [ "ab"; "abcd" ] "abcd" [ (1, 0, 4) ];
    v "leftlong010" [ "abcd"; "bcd"; "cd"; "b" ] "abcd" [ (0, 0, 4) ];
    v "leftlong040" [ "a"; "ab" ] "a" [ (0, 0, 1) ];
    v "leftlong050" [ "a"; "ab" ] "ab" [ (1, 0, 2) ];
    v "leftlong060" [ "ab"; "a" ] "a" [ (1, 0, 1) ];
    v "leftlong070" [ "ab"; "a" ] "ab" [ (0, 0, 2) ];
    v "leftlong100" [ "abcdefg"; "bcde"; "bcdef" ] "abcdef" [ (2, 1, 6) ];
    v "leftlong110" [ "abcdefg"; "bcdef"; "bcde" ] "abcdef" [ (1, 1, 6) ];
    v "leftlong300" [ "abcd"; "b"; "bce" ] "abce" [ (2, 1, 4) ];
    v "leftlong310" [ "a"; "abcdefghi"; "hz"; "abcdefgh" ] "abcdefghz" [ (3, 0, 8) ];
    v "leftlong320" [ "a"; "abab" ] "abab" [ (1, 0, 4) ];
    v "leftlong330" [ "abcd"; "b"; "ce" ] "abce" [ (1, 1, 2); (2, 2, 4) ];
    v "leftlong340" [ "a"; "ab" ] "xayabbbz" [ (0, 1, 2); (1, 3, 5) ];
  ]

(* ASCII_CASE_INSENSITIVE: identical under every match kind. *)
let ascii_case_insensitive =
  [
    v "acasei000" [ "a" ] "A" [ (0, 0, 1) ];
    v "acasei010" [ "Samwise" ] "SAMWISE" [ (0, 0, 7) ];
    v "acasei011" [ "Samwise" ] "SAMWISE.abcd" [ (0, 0, 7) ];
    v "acasei020" [ "fOoBaR" ] "quux foobar baz" [ (0, 5, 11) ];
  ]

let ascii_case_insensitive_non_overlapping =
  [
    v "acasei_nover000" [ "foo"; "FOO" ] "fOo" [ (0, 0, 3) ];
    v "acasei_nover001" [ "FOO"; "foo" ] "fOo" [ (0, 0, 3) ];
    v "acasei_nover010" [ "abc"; "def" ] "abcdef" [ (0, 0, 3); (1, 3, 6) ];
  ]

let ascii_case_insensitive_overlapping =
  [
    v "acasei_over000" [ "foo"; "FOO" ] "fOo" [ (0, 0, 3); (1, 0, 3) ];
    v "acasei_over001" [ "FOO"; "foo" ] "fOo" [ (0, 0, 3); (1, 0, 3) ];
    (* BurntSushi/aho-corasick#68: a duplicate (1, 3, 6) used to be reported *)
    v "acasei_over010" [ "abc"; "def"; "abcdef" ] "abcdef"
      [ (0, 0, 3); (2, 0, 6); (1, 3, 6) ];
  ]

(* REGRESSION: identical under every match kind. *)
let regression =
  [
    v "regression010" [ "inf"; "ind" ] "infind" [ (0, 0, 3); (1, 3, 6) ];
    v "regression020" [ "ind"; "inf" ] "infind" [ (1, 0, 3); (0, 3, 6) ];
    v "regression030" [ "libcore/"; "libstd/" ] "libcore/char/methods.rs" [ (0, 0, 8) ];
    v "regression040" [ "libstd/"; "libcore/" ] "libcore/char/methods.rs" [ (1, 0, 8) ];
    v "regression050" [ "\x00\x00\x01"; "\x00\x00\x00" ] "\x00\x00\x00" [ (1, 0, 3) ];
    v "regression060" [ "\x00\x00\x00"; "\x00\x00\x01" ] "\x00\x00\x00" [ (0, 0, 3) ];
  ]

(* Examples from the crate's API documentation (docs.rs/aho-corasick). *)
let rust_docs_overlapping =
  [
    v "docs_find_overlapping_iter" [ "append"; "appendage"; "app" ]
      "append the app to the appendage"
      [ (2, 0, 3); (0, 0, 6); (2, 11, 14); (2, 22, 25); (0, 22, 28); (1, 22, 31) ];
  ]

let rust_docs_standard =
  [
    v "docs_find_iter" [ "apple"; "maple"; "Snapple" ]
      "Nobody likes maple in their apple flavored Snapple."
      [ (1, 13, 18); (0, 28, 33); (2, 43, 50) ];
    v "docs_stream_find_iter" [ "append"; "appendage"; "app" ]
      "append the app to the appendage"
      [ (2, 0, 3); (2, 11, 14); (2, 22, 25) ];
    v "docs_match_kind_standard" [ "Samwise"; "Sam" ] "Samwise" [ (1, 0, 3) ];
  ]

let rust_docs_leftmost_longest =
  [
    v "docs_replace_all_leftmost_longest" [ "append"; "appendage"; "app" ]
      "append the app to the appendage"
      [ (0, 0, 6); (2, 11, 14); (1, 22, 31) ];
    v "docs_match_kind_leftmost_longest" [ "Samwise"; "Sam" ] "Samwise" [ (0, 0, 7) ];
  ]

(* ---------- pyahocorasick iter_long ---------- *)

(* pyahocorasick reports (inclusive end index, value); converted here to
   half-open offsets. Its iter_long answers coincide with leftmost-longest
   on every documented case. *)
let pyahocorasick_iter_long =
  [
    v "pyahocorasick_docs" [ "he"; "her"; "here" ] "he here her"
      [ (0, 0, 2); (2, 3, 7); (1, 8, 11) ];
    v "pyahocorasick_issue133_1" [ "b"; "abc" ] "abb" [ (0, 1, 2); (0, 2, 3) ];
    v "pyahocorasick_issue133_2" [ "b"; "c"; "abd" ] "abc" [ (0, 1, 2); (1, 2, 3) ];
    v "pyahocorasick_issue133_3" [ "trimethoprim"; "sulfamethoxazole"; "meth" ]
      "sulfamethoxazole and trimethoprim"
      [ (1, 0, 16); (0, 21, 33) ];
    v "pyahocorasick_issue133_4" [ "is"; "this"; "is this a dream?" ]
      "is this a test?"
      [ (0, 0, 2); (1, 3, 7) ];
    v "pyahocorasick_issue133_5" [ "th"; "this"; "is this a dream?" ]
      "is this a test?"
      [ (1, 3, 7) ];
  ]

(* ---------- the vectors this library documents ---------- *)

let documented_find_all =
  [
    v "doc_ushers" [ "he"; "she"; "his"; "hers" ] "ushers" [ (1, 1, 4); (0, 2, 4); (3, 2, 6) ];
    v "doc_nested" [ "a"; "ab"; "abc" ] "abca" [ (0, 0, 1); (1, 0, 2); (2, 0, 3); (0, 3, 4) ];
    v "doc_self_overlap" [ "aa" ] "aaaa" [ (0, 0, 2); (0, 1, 3); (0, 2, 4) ];
    v "doc_samwise" [ "Sam"; "Samwise" ] "Samwise" [ (0, 0, 3); (1, 0, 7) ];
    v "doc_ba" [ "b"; "ba" ] "aba" [ (0, 1, 2); (1, 1, 3) ];
    v "doc_abbc" [ "ab"; "bc" ] "abc" [ (0, 0, 2); (1, 1, 3) ];
    v "doc_duplicates" [ "x"; "x" ] "ax" [ (0, 1, 2); (1, 1, 2) ];
    v "doc_boundary" [ "abc" ] "xxabc-abc" [ (0, 2, 5); (0, 6, 9) ];
    v "doc_utf8" [ "\xc3\xa9" ] "caf\xc3\xa9 au lait" [ (0, 3, 5) ];
  ]

let documented_leftmost_longest =
  [
    v "doc_ushers" [ "he"; "she"; "his"; "hers" ] "ushers" [ (1, 1, 4) ];
    v "doc_nested" [ "a"; "ab"; "abc" ] "abca" [ (2, 0, 3); (0, 3, 4) ];
    v "doc_self_overlap" [ "aa" ] "aaaa" [ (0, 0, 2); (0, 2, 4) ];
    v "doc_samwise" [ "Sam"; "Samwise" ] "Samwise" [ (1, 0, 7) ];
    v "doc_ba" [ "b"; "ba" ] "aba" [ (1, 1, 3) ];
    v "doc_abbc" [ "ab"; "bc" ] "abc" [ (0, 0, 2) ];
    v "doc_duplicates" [ "x"; "x" ] "ax" [ (0, 1, 2) ];
    v "doc_boundary" [ "abc" ] "xxabc-abc" [ (0, 2, 5); (0, 6, 9) ];
    v "doc_utf8" [ "\xc3\xa9" ] "caf\xc3\xa9 au lait" [ (0, 3, 5) ];
  ]

let documented_ignore_case =
  [ v "doc_ignore_case" [ "Rust" ] "rust RUST rUsT" [ (0, 0, 4); (0, 5, 9); (0, 10, 14) ] ]

(* ---------- running the vectors ---------- *)

let triple_t = Alcotest.(triple int int int)
let triples ms = List.map (fun m -> (m.pattern, m.start, m.stop)) ms

(* [s] cut into pieces of at most [n] bytes. *)
let chunks n s =
  let len = String.length s in
  let rec go i acc =
    if i >= len then List.rev acc
    else
      let k = min n (len - i) in
      go (i + k) (String.sub s i k :: acc)
  in
  go 0 []

let feed_all feed append empty st0 pieces =
  List.fold_left
    (fun (st, acc) piece ->
      let st, out = feed st piece in
      (st, append acc out))
    (st0, empty) pieces

(* A way of searching that must reproduce a vector. *)
type search = {
  label : string;
  run : ignore_case:bool -> string list -> string -> (int * int * int) list;
}

let search label run = { label; run }

let whole label f =
  search label (fun ~ignore_case ps s -> triples (f (build ~ignore_case ps) s))

let s_find_all = whole "find_all" find_all
let s_find_iter = whole "find_iter" (fun t s -> List.of_seq (find_iter t s))

let s_stream_feed n =
  whole (Printf.sprintf "Stream.feed/%d" n) (fun t s ->
      snd (feed_all (Stream.feed t) ( @ ) [] (Stream.start t) (chunks n s)))

let s_nonoverlapping =
  whole "Stream.feed_nonoverlapping" (fun t s ->
      snd (Stream.feed_nonoverlapping t (Stream.start t) s))

let s_nonoverlapping_stream n =
  whole (Printf.sprintf "Stream.feed_nonoverlapping/%d" n) (fun t s ->
      snd
        (feed_all (Stream.feed_nonoverlapping t) ( @ ) [] (Stream.start t)
           (chunks n s)))

let s_leftmost_longest = whole "find_leftmost_longest" find_leftmost_longest

let s_leftmost_longest_stream n =
  whole (Printf.sprintf "Stream.Leftmost_longest/%d" n) (fun t s ->
      let module L = Stream.Leftmost_longest in
      let st, ms = feed_all (L.feed t) ( @ ) [] (L.start t) (chunks n s) in
      ms @ L.flush st)

(* Every function reporting overlapping matches. *)
let overlapping_searches = [ s_find_all; s_find_iter; s_stream_feed 1; s_stream_feed 3 ]

(* Every function with standard non-overlapping semantics. Rust runs its
   stream tests through a 1-byte BufReader; chunk size 1 is the same. *)
let standard_searches =
  [ s_nonoverlapping; s_nonoverlapping_stream 1; s_nonoverlapping_stream 3 ]

(* Every function with leftmost-longest semantics. *)
let leftmost_longest_searches =
  [ s_leftmost_longest; s_leftmost_longest_stream 1; s_leftmost_longest_stream 3 ]

let check_matches ?(ignore_case = false) searches vectors () =
  List.iter
    (fun vec ->
      List.iter
        (fun s ->
          Alcotest.(check (list triple_t))
            (vec.name ^ " via " ^ s.label)
            vec.expected
            (s.run ~ignore_case vec.patterns vec.haystack))
        searches;
      Alcotest.(check bool)
        (vec.name ^ " via mem")
        (vec.expected <> [])
        (mem (build ~ignore_case vec.patterns) vec.haystack))
    vectors

(* The text with each expected match [(p, a, b)] replaced by "<p>". *)
let splice s expected =
  let buf = Buffer.create (String.length s) in
  let pos =
    List.fold_left
      (fun pos (p, a, b) ->
        Buffer.add_substring buf s pos (a - pos);
        Buffer.add_string buf (Printf.sprintf "<%d>" p);
        b)
      0 expected
  in
  Buffer.add_substring buf s pos (String.length s - pos);
  Buffer.contents buf

(* Leftmost-longest vectors also pin down replacement, whole and streamed. *)
let check_replace ?(ignore_case = false) vectors () =
  List.iter
    (fun vec ->
      let t = build ~ignore_case vec.patterns in
      let f m = Printf.sprintf "<%d>" m.pattern in
      let expected = splice vec.haystack vec.expected in
      Alcotest.(check string)
        (vec.name ^ " via replace_all")
        expected
        (replace_all t ~f vec.haystack);
      let module R = Stream.Replace in
      List.iter
        (fun n ->
          let st, out =
            feed_all (R.feed t) ( ^ ) "" (R.start t ~f) (chunks n vec.haystack)
          in
          Alcotest.(check string)
            (Printf.sprintf "%s via Stream.Replace/%d" vec.name n)
            expected (out ^ R.flush st))
        [ 1; 3 ])
    vectors

let all_kinds = basics @ regression

(* The crate's standalone regression tests. *)
let test_rust_regressions () =
  (* BurntSushi/aho-corasick#44: case folding must not blow up construction *)
  let t = build ~ignore_case:true [ "Tsubaki House-Triple Shot Vol01校花三姐妹" ] in
  Alcotest.(check bool) "issue 44" false (mem t "");
  (* BurntSushi/aho-corasick#53: rare-byte prefilter false negative *)
  let t = build [ "ab/j/"; "x/" ] in
  Alcotest.(check bool) "issue 53" true (mem t "ab/j/");
  (* regression_case_insensitive_prefilter: every two-letter needle, folded *)
  for c = Char.code 'a' to Char.code 'z' do
    for c2 = Char.code 'a' to Char.code 'z' do
      let needle = Printf.sprintf "%c%c" (Char.chr c) (Char.chr c2) in
      let t = build ~ignore_case:true [ needle ] in
      Alcotest.(check int)
        ("case-insensitive " ^ needle)
        1
        (List.length (find_all t (String.uppercase_ascii needle)))
    done
  done;
  (* BurntSushi/aho-corasick#64: a match straddling the reader's buffer
     boundary was lost on streams. 100 000 zero bytes with "1234j" at
     offset 65 535, read 8 KiB at a time. *)
  let magic = "1234j" and offset = 65_535 in
  let input = Bytes.make 100_000 '\000' in
  Bytes.blit_string magic 0 input offset (String.length magic);
  let input = Bytes.to_string input in
  let t = build [ magic ] in
  let expected = [ (0, offset, offset + String.length magic) ] in
  Alcotest.(check (list triple_t)) "issue 64 whole" expected (triples (find_all t input));
  let _, streamed =
    feed_all (Stream.feed_nonoverlapping t) ( @ ) [] (Stream.start t) (chunks 8192 input)
  in
  Alcotest.(check (list triple_t)) "issue 64 streamed" expected (triples streamed)

let () =
  Alcotest.run "conformance"
    [
      ( "rust aho-corasick: every match kind",
        [
          Alcotest.test_case "overlapping" `Quick
            (check_matches overlapping_searches all_kinds);
          Alcotest.test_case "standard" `Quick (check_matches standard_searches all_kinds);
          Alcotest.test_case "leftmost-longest" `Quick
            (check_matches leftmost_longest_searches all_kinds);
          Alcotest.test_case "replace" `Quick (check_replace all_kinds);
          Alcotest.test_case "case-insensitive, overlapping" `Quick
            (check_matches ~ignore_case:true overlapping_searches ascii_case_insensitive);
          Alcotest.test_case "case-insensitive, standard" `Quick
            (check_matches ~ignore_case:true standard_searches ascii_case_insensitive);
          Alcotest.test_case "case-insensitive, leftmost-longest" `Quick
            (check_matches ~ignore_case:true leftmost_longest_searches
               ascii_case_insensitive);
          Alcotest.test_case "standalone regressions" `Quick test_rust_regressions;
        ] );
      ( "rust aho-corasick: overlapping",
        [
          Alcotest.test_case "OVERLAPPING" `Quick
            (check_matches overlapping_searches (overlapping @ rust_docs_overlapping));
          Alcotest.test_case "ASCII_CASE_INSENSITIVE_OVERLAPPING" `Quick
            (check_matches ~ignore_case:true overlapping_searches
               ascii_case_insensitive_overlapping);
        ] );
      ( "rust aho-corasick: standard non-overlapping",
        [
          Alcotest.test_case "STANDARD" `Quick
            (check_matches standard_searches (standard @ rust_docs_standard));
          Alcotest.test_case "NON_OVERLAPPING" `Quick
            (check_matches standard_searches non_overlapping);
          Alcotest.test_case "ASCII_CASE_INSENSITIVE_NON_OVERLAPPING" `Quick
            (check_matches ~ignore_case:true standard_searches
               ascii_case_insensitive_non_overlapping);
        ] );
      ( "rust aho-corasick: leftmost-longest",
        [
          Alcotest.test_case "LEFTMOST" `Quick
            (check_matches leftmost_longest_searches leftmost);
          Alcotest.test_case "LEFTMOST_LONGEST" `Quick
            (check_matches leftmost_longest_searches
               (leftmost_longest @ rust_docs_leftmost_longest));
          Alcotest.test_case "NON_OVERLAPPING" `Quick
            (check_matches leftmost_longest_searches non_overlapping);
          Alcotest.test_case "ASCII_CASE_INSENSITIVE_NON_OVERLAPPING" `Quick
            (check_matches ~ignore_case:true leftmost_longest_searches
               ascii_case_insensitive_non_overlapping);
          Alcotest.test_case "replace" `Quick
            (check_replace
               (leftmost @ leftmost_longest @ non_overlapping @ rust_docs_leftmost_longest));
        ] );
      ( "pyahocorasick",
        [
          Alcotest.test_case "iter_long = leftmost-longest" `Quick
            (check_matches leftmost_longest_searches pyahocorasick_iter_long);
        ] );
      ( "documented vectors",
        [
          Alcotest.test_case "find_all" `Quick
            (check_matches overlapping_searches documented_find_all);
          Alcotest.test_case "find_leftmost_longest" `Quick
            (check_matches leftmost_longest_searches documented_leftmost_longest);
          Alcotest.test_case "replace" `Quick (check_replace documented_leftmost_longest);
          Alcotest.test_case "ignore_case" `Quick
            (check_matches ~ignore_case:true
               (overlapping_searches @ standard_searches @ leftmost_longest_searches)
               documented_ignore_case);
        ] );
    ]
