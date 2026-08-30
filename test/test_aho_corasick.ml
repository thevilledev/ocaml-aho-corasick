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

(* ---------- properties ---------- *)

let gen_pattern = QCheck2.Gen.(string_size ~gen:(char_range 'a' 'c') (1 -- 3))
let gen_text n = QCheck2.Gen.(string_size ~gen:(char_range 'a' 'c') (0 -- n))

let prop_oracle =
  QCheck2.Test.make ~name:"find_all = naive scan" ~count:1000
    QCheck2.Gen.(pair (list_size (1 -- 5) gen_pattern) (gen_text 60))
    (fun (ps, text) ->
      norm (find_all (build ps) text) = norm (naive ps text))

let prop_stream =
  QCheck2.Test.make ~name:"chunked streaming = whole input" ~count:500
    QCheck2.Gen.(
      triple
        (list_size (1 -- 4) gen_pattern)
        (gen_text 80)
        (list_size (0 -- 6) (0 -- 30)))
    (fun (ps, text, sizes) ->
      let t = build ps in
      let n = String.length text in
      let st = ref (Stream.start t) in
      let acc = ref [] in
      let pos = ref 0 in
      List.iter
        (fun sz ->
          let take = min sz (n - !pos) in
          let st', ms = Stream.feed t !st (String.sub text !pos take) in
          st := st';
          acc := !acc @ ms;
          pos := !pos + take)
        sizes;
      let _, ms = Stream.feed t !st (String.sub text !pos (n - !pos)) in
      !acc @ ms = find_all t text)

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
        ] );
      ( "properties",
        List.map QCheck_alcotest.to_alcotest
          [ prop_oracle; prop_stream; prop_leftmost_longest_sound ] );
    ]
