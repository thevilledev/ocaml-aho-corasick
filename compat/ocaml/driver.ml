(* Differential-test and benchmark driver for this library.

   [driver cases]  reads cases from stdin and prints one result line per
                   case and mode; compat/README.md describes both formats.
   [driver bench]  times one search mode over a patterns file and a
                   haystack file and prints one tab-separated result line.

   The Rust and Python drivers under compat/ speak the same formats, so
   the outputs can be compared directly. *)

open Aho_corasick

let usage () =
  prerr_endline
    "usage: driver cases < cases.tsv\n\
    \       driver bench <mode> <patterns-file> <haystack-file> [--seconds S] [--chunk N]";
  exit 2

let hex_decode s =
  let n = String.length s in
  if n mod 2 <> 0 then failwith ("odd-length hex: " ^ s);
  String.init (n / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub s (2 * i) 2)))

let hex_encode s =
  let buf = Buffer.create (2 * String.length s) in
  String.iter (fun c -> Buffer.add_string buf (Printf.sprintf "%02x" (Char.code c))) s;
  Buffer.contents buf

type case = {
  id : string;
  ignore_case : bool;
  patterns : string list;
  input : string;
  chunks : int list;
}

let parse_case line =
  if line = "" || line.[0] = '#' then None
  else
    match String.split_on_char '\t' line with
    | [ id; flags; patterns; input; chunks ] ->
      Some
        {
          id;
          ignore_case = String.contains flags 'i';
          patterns =
            (if patterns = "" then []
             else List.map hex_decode (String.split_on_char ',' patterns));
          input = hex_decode input;
          chunks =
            (if chunks = "" then []
             else List.map int_of_string (String.split_on_char ',' chunks));
        }
    | _ -> failwith ("malformed case line: " ^ line)

(* Cut [input] at the given sizes; whatever remains is a final chunk. *)
let split_chunks input sizes =
  let n = String.length input in
  let pos = ref 0 in
  let pieces =
    List.map
      (fun size ->
        let take = min size (n - !pos) in
        let piece = String.sub input !pos take in
        pos := !pos + take;
        piece)
      sizes
  in
  pieces @ [ String.sub input !pos (n - !pos) ]

(* [input] in pieces of [n] bytes. *)
let chunks_of n input =
  let len = String.length input in
  let rec go i acc =
    if i >= len then List.rev acc
    else
      let k = min n (len - i) in
      go (i + k) (String.sub input i k :: acc)
  in
  go 0 []

let feed_all feed append empty st0 pieces =
  List.fold_left
    (fun (st, acc) piece ->
      let st, out = feed st piece in
      (st, append acc out))
    (st0, empty) pieces

let fmt_matches = function
  | [] -> "-"
  | ms ->
    String.concat " "
      (List.map (fun m -> Printf.sprintf "%d:%d:%d" m.pattern m.start m.stop) ms)

let replacement m = Printf.sprintf "<%d>" m.pattern

let run_case c =
  let emit mode result = Printf.printf "%s\t%s\t%s\n" c.id mode result in
  let t = build ~ignore_case:c.ignore_case c.patterns in
  let pieces = split_chunks c.input c.chunks in
  emit "overlapping" (fmt_matches (find_all t c.input));
  emit "overlapping_stream"
    (fmt_matches (snd (feed_all (Stream.feed t) ( @ ) [] (Stream.start t) pieces)));
  emit "standard" (fmt_matches (snd (Stream.feed_nonoverlapping t (Stream.start t) c.input)));
  emit "standard_stream"
    (fmt_matches
       (snd (feed_all (Stream.feed_nonoverlapping t) ( @ ) [] (Stream.start t) pieces)));
  emit "leftmost_longest" (fmt_matches (find_leftmost_longest t c.input));
  (let module L = Stream.Leftmost_longest in
   let st, ms = feed_all (L.feed t) ( @ ) [] (L.start t) pieces in
   emit "leftmost_longest_stream" (fmt_matches (ms @ L.flush st)));
  emit "replace" (hex_encode (replace_all t ~f:replacement c.input));
  (let module R = Stream.Replace in
   let st, out = feed_all (R.feed t) ( ^ ) "" (R.start t ~f:replacement) pieces in
   emit "replace_stream" (hex_encode (out ^ R.flush st)));
  emit "is_match" (string_of_bool (mem t c.input));
  emit "first"
    (fmt_matches
       (match find_iter t c.input () with Seq.Cons (m, _) -> [ m ] | Seq.Nil -> []));
  emit "first_leftmost_longest"
    (fmt_matches (match find_leftmost_longest t c.input with m :: _ -> [ m ] | [] -> []))

let run_cases () =
  let rec loop () =
    match In_channel.input_line stdin with
    | None -> ()
    | Some line ->
      Option.iter run_case (parse_case line);
      loop ()
  in
  loop ()

let read_file path = In_channel.with_open_bin path In_channel.input_all

let read_patterns path =
  List.filter (fun l -> l <> "") (String.split_on_char '\n' (read_file path))

let count_seq seq = Seq.fold_left (fun n _ -> n + 1) 0 seq

let count_stream feed t pieces =
  List.fold_left
    (fun (st, n) piece ->
      let st, ms = feed t st piece in
      (st, n + List.length ms))
    (Stream.start t, 0) pieces
  |> snd

let run_bench = function
  | mode :: patterns_file :: haystack_file :: options ->
    let patterns = read_patterns patterns_file and haystack = read_file haystack_file in
    let seconds = ref 2.0 and chunk = ref 4096 in
    let rec parse = function
      | "--seconds" :: s :: rest ->
        seconds := float_of_string s;
        parse rest
      | "--chunk" :: n :: rest ->
        chunk := int_of_string n;
        parse rest
      | [] -> ()
      | _ -> usage ()
    in
    parse options;
    let ns f = int_of_float (f *. 1e9) in
    let started = Unix.gettimeofday () in
    let t = build patterns in
    let build_ns = ns (Unix.gettimeofday () -. started) in
    let pieces = chunks_of !chunk haystack in
    let run () =
      match mode with
      | "overlapping" -> List.length (find_all t haystack)
      | "overlapping_iter" -> count_seq (find_iter t haystack)
      | "standard" -> List.length (snd (Stream.feed_nonoverlapping t (Stream.start t) haystack))
      | "leftmost_longest" -> List.length (find_leftmost_longest t haystack)
      | "is_match" -> if mem t haystack then 1 else 0
      | "replace" -> String.length (replace_all t ~f:replacement haystack)
      | "overlapping_stream" -> count_stream Stream.feed t pieces
      | "standard_stream" -> count_stream Stream.feed_nonoverlapping t pieces
      | "leftmost_longest_stream" ->
        let module L = Stream.Leftmost_longest in
        let st, n =
          List.fold_left
            (fun (st, n) piece ->
              let st, ms = L.feed t st piece in
              (st, n + List.length ms))
            (L.start t, 0) pieces
        in
        n + List.length (L.flush st)
      | _ -> usage ()
    in
    let count = run () in
    let samples = ref [] and iters = ref 0 in
    let started = Unix.gettimeofday () in
    while Unix.gettimeofday () -. started < !seconds || !iters < 3 do
      let t0 = Unix.gettimeofday () in
      let c = run () in
      samples := ns (Unix.gettimeofday () -. t0) :: !samples;
      incr iters;
      if c <> count then failwith "count changed between runs"
    done;
    let samples = Array.of_list !samples in
    Array.sort compare samples;
    Printf.printf "ocaml/aho-corasick\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n" mode
      (String.length haystack) !iters build_ns samples.(0)
      samples.(Array.length samples / 2)
      count
  | _ -> usage ()

let () =
  match Array.to_list Sys.argv with
  | _ :: "cases" :: [] -> run_cases ()
  | _ :: "bench" :: args -> run_bench args
  | _ -> usage ()
