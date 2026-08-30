type t = {
  trans : (int, int) Hashtbl.t; (* (node lsl 8) lor byte -> node *)
  fail : int array;
  out : int array array; (* pattern indexes ending exactly at a node *)
  dlink : int array; (* nearest suffix node with matches, or -1 *)
  pat_len : int array;
  patterns : string array;
  ignore_case : bool;
}

type match_ = { pattern : int; start : int; stop : int }

let build ?(ignore_case = false) pattern_list =
  let patterns = Array.of_list pattern_list in
  Array.iter
    (fun p ->
      if p = "" then invalid_arg "Aho_corasick.build: empty pattern")
    patterns;
  let fold p = if ignore_case then String.lowercase_ascii p else p in
  (* growable per-node storage while the trie is built *)
  let cap = ref 16 in
  let children = ref (Array.make !cap []) in
  let out_l = ref (Array.make !cap []) in
  let count = ref 1 (* root = 0 *) in
  let trans = Hashtbl.create 256 in
  let new_node () =
    if !count >= !cap then begin
      let ncap = !cap * 2 in
      let ch = Array.make ncap [] and ol = Array.make ncap [] in
      Array.blit !children 0 ch 0 !cap;
      Array.blit !out_l 0 ol 0 !cap;
      children := ch;
      out_l := ol;
      cap := ncap
    end;
    let id = !count in
    incr count;
    id
  in
  Array.iteri
    (fun pi p ->
      let node = ref 0 in
      String.iter
        (fun ch ->
          let c = Char.code ch in
          let key = (!node lsl 8) lor c in
          match Hashtbl.find_opt trans key with
          | Some v -> node := v
          | None ->
            let v = new_node () in
            Hashtbl.add trans key v;
            !children.(!node) <- (c, v) :: !children.(!node);
            node := v)
        (fold p);
      !out_l.(!node) <- pi :: !out_l.(!node))
    patterns;
  let n = !count in
  let fail = Array.make n 0 in
  let dlink = Array.make n (-1) in
  let out = Array.init n (fun i -> Array.of_list (List.rev !out_l.(i))) in
  (* breadth-first computation of failure and dictionary-suffix links *)
  let q = Queue.create () in
  List.iter (fun (_, v) -> Queue.add v q) !children.(0);
  let rec goto s c =
    match Hashtbl.find_opt trans ((s lsl 8) lor c) with
    | Some v -> v
    | None -> if s = 0 then 0 else goto fail.(s) c
  in
  while not (Queue.is_empty q) do
    let u = Queue.pop q in
    dlink.(u) <-
      (if Array.length out.(fail.(u)) > 0 then fail.(u) else dlink.(fail.(u)));
    List.iter
      (fun (c, v) ->
        fail.(v) <- goto fail.(u) c;
        Queue.add v q)
      !children.(u)
  done;
  {
    trans;
    fail;
    out;
    dlink;
    pat_len = Array.map String.length patterns;
    patterns;
    ignore_case;
  }

let pattern_count t = Array.length t.patterns

let pattern t i =
  if i < 0 || i >= Array.length t.patterns then
    invalid_arg "Aho_corasick.pattern: index out of bounds";
  t.patterns.(i)

let byte t s i =
  let c = Char.code (String.unsafe_get s i) in
  if t.ignore_case && c >= 0x41 && c <= 0x5a then c + 0x20 else c

let step t s c =
  let rec go s =
    match Hashtbl.find_opt t.trans ((s lsl 8) lor c) with
    | Some v -> v
    | None -> if s = 0 then 0 else go t.fail.(s)
  in
  go s

(* Prepend a match_ for every pattern ending at [node] (own outputs,
   then the dictionary-suffix chain) onto [acc]. [stop] is absolute. *)
let prepend_matches t node stop acc =
  let acc = ref acc in
  let add p = acc := { pattern = p; start = stop - t.pat_len.(p); stop } :: !acc in
  Array.iter add t.out.(node);
  let d = ref t.dlink.(node) in
  while !d >= 0 do
    Array.iter add t.out.(!d);
    d := t.dlink.(!d)
  done;
  !acc

let scan t ?(node = 0) ?(base = 0) s =
  let acc = ref [] and st = ref node in
  for i = 0 to String.length s - 1 do
    st := step t !st (byte t s i);
    acc := prepend_matches t !st (base + i + 1) !acc
  done;
  (!st, List.rev !acc)

let find_all t s = snd (scan t s)

let find_iter t s =
  let n = String.length s in
  let rec next i node pending () =
    match pending with
    | m :: rest -> Seq.Cons (m, next i node rest)
    | [] ->
      if i >= n then Seq.Nil
      else begin
        let node = step t node (byte t s i) in
        let ms = List.rev (prepend_matches t node (i + 1) []) in
        next (i + 1) node ms ()
      end
  in
  next 0 0 []

let find_leftmost_longest t s =
  let all = find_all t s in
  let sorted =
    List.sort
      (fun a b ->
        if a.start <> b.start then compare a.start b.start
        else compare (b.stop - b.start) (a.stop - a.start))
      all
  in
  let rec pick last acc = function
    | [] -> List.rev acc
    | m :: rest ->
      if m.start >= last then pick m.stop (m :: acc) rest
      else pick last acc rest
  in
  pick 0 [] sorted

let mem t s =
  let n = String.length s in
  let rec go i node =
    if i >= n then false
    else begin
      let node = step t node (byte t s i) in
      if Array.length t.out.(node) > 0 || t.dlink.(node) >= 0 then true
      else go (i + 1) node
    end
  in
  go 0 0

let replace_all t ~f s =
  let ms = find_leftmost_longest t s in
  let buf = Buffer.create (String.length s) in
  let pos = ref 0 in
  List.iter
    (fun m ->
      Buffer.add_substring buf s !pos (m.start - !pos);
      Buffer.add_string buf (f m);
      pos := m.stop)
    ms;
  Buffer.add_substring buf s !pos (String.length s - !pos);
  Buffer.contents buf

module Stream = struct
  type state = { node : int; pos : int }

  let start _t = { node = 0; pos = 0 }

  let feed t st chunk =
    let node, matches = scan t ~node:st.node ~base:st.pos chunk in
    ({ node; pos = st.pos + String.length chunk }, matches)

  let pos st = st.pos
end
