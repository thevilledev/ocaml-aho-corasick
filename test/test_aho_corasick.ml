open Aho_corasick

let m pattern start stop = { pattern; start; stop }

let match_pp fmt mt =
  Format.fprintf fmt "{pattern=%d; %d..%d}" mt.pattern mt.start mt.stop

let match_t = Alcotest.testable match_pp ( = )
let matches = Alcotest.(list match_t)

(* Reference implementation: scan each pattern independently. *)
let naive patterns text =
  List.concat
    (List.mapi
       (fun pi p ->
         let lp = String.length p and n = String.length text in
         let acc = ref [] in
         for i = 0 to n - lp do
           if String.sub text i lp = p then acc := m pi i (i + lp) :: !acc
         done;
         List.rev !acc)
       patterns)

let norm = List.sort compare

(* ---------- classic cases ---------- *)

let test_ushers () =
  let t = build [ "he"; "she"; "his"; "hers" ] in
  Alcotest.check matches "ushers"
    [ m 1 1 4; m 0 2 4; m 3 2 6 ]
    (find_all t "ushers");
  Alcotest.(check bool) "mem" true (mem t "ushers");
  Alcotest.(check bool) "no match" false (mem t "xyz")

let test_overlapping () =
  let t = build [ "aa" ] in
  Alcotest.check matches "aaaa overlaps"
    [ m 0 0 2; m 0 1 3; m 0 2 4 ]
    (find_all t "aaaa");
  let t2 = build [ "a"; "ab"; "abc" ] in
  Alcotest.check matches "nested at same end"
    [ m 0 0 1; m 1 0 2; m 2 0 3; m 0 3 4 ]
    (find_all t2 "abca")

let test_duplicates () =
  let t = build [ "x"; "x" ] in
  Alcotest.check matches "both indexes" [ m 0 1 2; m 1 1 2 ] (find_all t "ax")

let test_empty_patterns () =
  let t = build [] in
  Alcotest.check matches "matches nothing" [] (find_all t "anything");
  Alcotest.(check bool) "mem nothing" false (mem t "anything");
  Alcotest.check_raises "empty pattern"
    (Invalid_argument "Aho_corasick.build: empty pattern") (fun () ->
      ignore (build [ "ok"; "" ]))

let test_pattern_accessors () =
  let t = build [ "he"; "she" ] in
  Alcotest.(check int) "count" 2 (pattern_count t);
  Alcotest.(check string) "pattern 1" "she" (pattern t 1);
  Alcotest.check_raises "oob"
    (Invalid_argument "Aho_corasick.pattern: index out of bounds") (fun () ->
      ignore (pattern t 2))

let test_ignore_case () =
  let t = build ~ignore_case:true [ "Rust" ] in
  Alcotest.check matches "three case variants"
    [ m 0 0 4; m 0 5 9; m 0 10 14 ]
    (find_all t "rust RUST rUsT");
  let exact = build [ "Rust" ] in
  Alcotest.check matches "exact is case-sensitive" [] (find_all exact "rust")

(* ---------- leftmost-longest ---------- *)

let test_leftmost_longest () =
  let t = build [ "a"; "abc"; "b"; "bcd" ] in
  Alcotest.check matches "prefers longest at leftmost start"
    [ m 1 0 3 ]
    (find_leftmost_longest t "abcd" |> List.filter (fun x -> x.stop <= 3));
  let t2 = build [ "ab"; "bc" ] in
  Alcotest.check matches "greedy left" [ m 0 0 2 ] (find_leftmost_longest t2 "abc");
  let t3 = build [ "b"; "ba" ] in
  Alcotest.check matches "longest among same start"
    [ m 1 1 3 ]
    (find_leftmost_longest t3 "aba");
  let t4 = build [ "cat"; "dog" ] in
  Alcotest.check matches "disjoint"
    [ m 0 0 3; m 1 8 11 ]
    (find_leftmost_longest t4 "cat and dog")

let test_replace_all () =
  let t = build [ "cat"; "dog" ] in
  Alcotest.(check string)
    "replace words" "[0] and [1]"
    (replace_all t "cat and dog" ~f:(fun mt -> Printf.sprintf "[%d]" mt.pattern));
  let t2 = build [ "aa" ] in
  Alcotest.(check string)
    "non-overlapping replacement" "XX"
    (replace_all t2 "aaaa" ~f:(fun _ -> "X"));
  Alcotest.(check string)
    "no matches untouched" "hello"
    (replace_all t2 "hello" ~f:(fun _ -> "X"))

(* ---------- iter and streaming ---------- *)

let test_find_iter () =
  let t = build [ "he"; "she"; "his"; "hers" ] in
  Alcotest.check matches "iter = all" (find_all t "ushers")
    (List.of_seq (find_iter t "ushers"));
  (* laziness: taking the first match doesn't need the whole input *)
  match find_iter t "she........................." () with
  | Seq.Cons (first, _) -> Alcotest.check match_t "first" (m 1 0 3) first
  | Seq.Nil -> Alcotest.fail "expected a match"

let test_stream_boundary () =
  let t = build [ "abc" ] in
  let st = Stream.start t in
  let st, m1 = Stream.feed t st "xxab" in
  Alcotest.check matches "nothing yet" [] m1;
  let st, m2 = Stream.feed t st "c-abc" in
  Alcotest.check matches "boundary + inner" [ m 0 2 5; m 0 6 9 ] m2;
  Alcotest.(check int) "pos" 9 (Stream.pos st)

let test_stream_nonoverlapping () =
  let t = build [ "aa" ] in
  let st = Stream.start t in
  let st, m1 = Stream.feed_nonoverlapping t st "aaa" in
  Alcotest.check matches "restarts after a match" [ m 0 0 2 ] m1;
  let _st, m2 = Stream.feed_nonoverlapping t st "a" in
  Alcotest.check matches "across the boundary" [ m 0 2 4 ] m2;
  (* Rust stream_find_iter (MatchKind::Standard): earliest end wins *)
  let t2 = build [ "Samwise"; "Sam" ] in
  let _st, ms = Stream.feed_nonoverlapping t2 (Stream.start t2) "Samwise" in
  Alcotest.check matches "earliest-ending match" [ m 1 0 3 ] ms

let test_stream_leftmost_longest () =
  let module L = Stream.Leftmost_longest in
  let t = build [ "b"; "ba" ] in
  let st = L.start t in
  let st, m1 = L.feed t st "ab" in
  Alcotest.check matches "b held back: ba may still form" [] m1;
  let st, m2 = L.feed t st "a" in
  Alcotest.check matches "resolved to the longest" [ m 1 1 3 ] m2;
  Alcotest.check matches "nothing left" [] (L.flush st);
  (* matches that nothing can outrank are not held back *)
  let t2 = build [ "a" ] in
  let st2, ms = L.feed t2 (L.start t2) "aaa" in
  Alcotest.check matches "no needless latency"
    [ m 0 0 1; m 0 1 2; m 0 2 3 ]
    ms;
  Alcotest.check matches "flush empty" [] (L.flush st2)

let test_stream_replace () =
  let module R = Stream.Replace in
  let t = build [ "sam"; "samwise" ] in
  let f _ = "[X]" in
  let st = R.start t ~f in
  let st, o1 = R.feed t st "say samw" in
  let st, o2 = R.feed t st "ise sam" in
  let o3 = R.flush st in
  Alcotest.(check string)
    "streamed = whole input"
    (replace_all t ~f "say samwise sam")
    (o1 ^ o2 ^ o3);
  Alcotest.(check string) "longest wins across chunks" "say [X] [X]" (o1 ^ o2 ^ o3)

(* ---------- properties ---------- *)

let gen_pattern = QCheck2.Gen.(string_size ~gen:(char_range 'a' 'c') (1 -- 3))
let gen_text n = QCheck2.Gen.(string_size ~gen:(char_range 'a' 'c') (0 -- n))

let prop_oracle =
  QCheck2.Test.make ~name:"find_all = naive scan" ~count:1000
    QCheck2.Gen.(pair (list_size (1 -- 5) gen_pattern) (gen_text 60))
    (fun (ps, text) ->
      norm (find_all (build ps) text) = norm (naive ps text))

(* Split [text] at [sizes] (whatever remains becomes a final chunk,
   so empty chunks and empty tails are exercised too) and feed the
   pieces, combining the per-chunk results with [append]. *)
let feed_chunked feed append empty st0 text sizes =
  let n = String.length text in
  let st = ref st0 and acc = ref empty and pos = ref 0 in
  let go take =
    let st', out = feed !st (String.sub text !pos take) in
    st := st';
    acc := append !acc out;
    pos := !pos + take
  in
  List.iter (fun sz -> go (min sz (n - !pos))) sizes;
  go (n - !pos);
  (!st, !acc)

let gen_chunked =
  QCheck2.Gen.(
    triple
      (list_size (1 -- 4) gen_pattern)
      (gen_text 80)
      (list_size (0 -- 6) (0 -- 30)))

let prop_stream =
  QCheck2.Test.make ~name:"chunked streaming = whole input" ~count:500
    gen_chunked (fun (ps, text, sizes) ->
      let t = build ps in
      let _, ms =
        feed_chunked (Stream.feed t) ( @ ) [] (Stream.start t) text sizes
      in
      ms = find_all t text)

(* Reference for [Stream.feed_nonoverlapping]: greedy earliest-end over
   find_all's ordering (end offset ascending; longest first per end). *)
let nonoverlapping_reference t text =
  let rec go last acc = function
    | [] -> List.rev acc
    | mt :: rest ->
      if mt.start >= last then go mt.stop (mt :: acc) rest
      else go last acc rest
  in
  go 0 [] (find_all t text)

let prop_stream_nonoverlapping =
  QCheck2.Test.make ~name:"chunked non-overlapping = greedy earliest-end"
    ~count:500 gen_chunked (fun (ps, text, sizes) ->
      let t = build ps in
      let _, ms =
        feed_chunked
          (Stream.feed_nonoverlapping t)
          ( @ ) [] (Stream.start t) text sizes
      in
      ms = nonoverlapping_reference t text)

let prop_stream_leftmost_longest =
  QCheck2.Test.make ~name:"chunked leftmost-longest = whole input" ~count:500
    gen_chunked (fun (ps, text, sizes) ->
      let t = build ps in
      let module L = Stream.Leftmost_longest in
      let st, ms = feed_chunked (L.feed t) ( @ ) [] (L.start t) text sizes in
      ms @ L.flush st = find_leftmost_longest t text)

let prop_stream_replace =
  QCheck2.Test.make ~name:"chunked replace = replace_all" ~count:500
    gen_chunked (fun (ps, text, sizes) ->
      let t = build ps in
      (* shrinking, growing and deleting replacements *)
      let f mt =
        if mt.pattern mod 2 = 0 then "" else Printf.sprintf "<%d>" mt.pattern
      in
      let module R = Stream.Replace in
      let st, out = feed_chunked (R.feed t) ( ^ ) "" (R.start t ~f) text sizes in
      out ^ R.flush st = replace_all t ~f text)

let prop_leftmost_longest_sound =
  QCheck2.Test.make ~name:"leftmost-longest is non-overlapping and maximal"
    ~count:500
    QCheck2.Gen.(pair (list_size (1 -- 5) gen_pattern) (gen_text 60))
    (fun (ps, text) ->
      let t = build ps in
      let sel = find_leftmost_longest t text in
      let all = find_all t text in
      (* non-overlapping, in order *)
      let rec ordered = function
        | a :: (b :: _ as rest) -> a.stop <= b.start && ordered rest
        | _ -> true
      in
      (* every selected match is a real match *)
      ordered sel && List.for_all (fun x -> List.mem x all) sel)

let () =
  Alcotest.run "aho-corasick"
    [
      ( "classic",
        [
          Alcotest.test_case "ushers" `Quick test_ushers;
          Alcotest.test_case "overlapping" `Quick test_overlapping;
          Alcotest.test_case "duplicate patterns" `Quick test_duplicates;
          Alcotest.test_case "empty inputs" `Quick test_empty_patterns;
          Alcotest.test_case "pattern accessors" `Quick test_pattern_accessors;
          Alcotest.test_case "ignore_case" `Quick test_ignore_case;
        ] );
      ( "leftmost-longest",
        [
          Alcotest.test_case "selection" `Quick test_leftmost_longest;
          Alcotest.test_case "replace_all" `Quick test_replace_all;
        ] );
      ( "streaming",
        [
          Alcotest.test_case "find_iter" `Quick test_find_iter;
          Alcotest.test_case "chunk boundary" `Quick test_stream_boundary;
          Alcotest.test_case "non-overlapping" `Quick test_stream_nonoverlapping;
          Alcotest.test_case "leftmost-longest" `Quick
            test_stream_leftmost_longest;
          Alcotest.test_case "replace" `Quick test_stream_replace;
        ] );
      ( "properties",
        List.map QCheck_alcotest.to_alcotest
          [
            prop_oracle;
            prop_stream;
            prop_stream_nonoverlapping;
            prop_stream_leftmost_longest;
            prop_stream_replace;
            prop_leftmost_longest_sound;
          ] );
    ]
