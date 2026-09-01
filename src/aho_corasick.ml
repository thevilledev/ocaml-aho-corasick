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

(* The single match the automaton sees first ending at [stop], if any:
   the longest one (a node's own outputs precede its dictionary-suffix
   chain, and [dlink] points at the deepest suffix with outputs). *)
let first_match t node stop =
  let at n =
    let p = t.out.(n).(0) in
    Some { pattern = p; start = stop - t.pat_len.(p); stop }
  in
  if Array.length t.out.(node) > 0 then at node
  else if t.dlink.(node) >= 0 then at t.dlink.(node)
  else None

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

  let feed_nonoverlapping t st chunk =
    let node = ref st.node and acc = ref [] in
    for i = 0 to String.length chunk - 1 do
      node := step t !node (byte t chunk i);
      match first_match t !node (st.pos + i + 1) with
      | Some m ->
        acc := m :: !acc;
        node := 0
      | None -> ()
    done;
    ({ node = !node; pos = st.pos + String.length chunk }, List.rev !acc)

  let pos st = st.pos

  (* Leftmost-longest cannot always decide a match the moment it ends: a
     longer match starting at or before it may still be in progress. But
     no match exceeds the longest pattern, so any match still unseen at
     scan position [pos] must start after [pos - max_len]; once scanning
     is [max_len] bytes past a candidate's start, nothing can outrank it.
     Hence streaming selection with lookahead bounded by [max_len]. *)
  type ll_state = {
    ll_node : int;
    ll_pos : int;
    ll_done : int; (* end of the last selected match *)
    ll_pending : match_ list; (* undecided candidates, best first *)
    ll_max : int; (* longest pattern length *)
  }

  (* The greedy order of {!find_leftmost_longest}: smallest start, then
     longest, then first-listed pattern. *)
  let candidate_order a b =
    if a.start <> b.start then compare a.start b.start
    else if a.stop <> b.stop then compare b.stop a.stop
    else compare a.pattern b.pattern

  let ll_start t =
    {
      ll_node = 0;
      ll_pos = 0;
      ll_done = 0;
      ll_pending = [];
      ll_max = Array.fold_left max 0 t.pat_len;
    }

  (* Select from the sorted candidates greedily, stopping at the first
     candidate that an unseen match (necessarily starting after
     [limit - max_len]) could still outrank; [max_int] at end of input
     selects everything. *)
  let ll_select max_len limit done_ pending =
    let rec go done_ acc = function
      | m :: rest when m.start + max_len <= limit ->
        let rest = List.filter (fun x -> x.start >= m.stop) rest in
        go m.stop (m :: acc) rest
      | rest -> (done_, List.rev acc, rest)
    in
    go done_ [] pending

  let ll_feed t st chunk =
    let node, ms = scan t ~node:st.ll_node ~base:st.ll_pos chunk in
    let pos = st.ll_pos + String.length chunk in
    let fresh = List.filter (fun m -> m.start >= st.ll_done) ms in
    let pending = List.sort candidate_order (st.ll_pending @ fresh) in
    let done_, selected, pending = ll_select st.ll_max pos st.ll_done pending in
    ( { st with ll_node = node; ll_pos = pos; ll_done = done_;
        ll_pending = pending },
      selected )

  let ll_flush st =
    let _, selected, _ = ll_select st.ll_max max_int st.ll_done st.ll_pending in
    selected

  module Leftmost_longest = struct
    type state = ll_state

    let start = ll_start
    let feed = ll_feed
    let flush = ll_flush
    let pos st = st.ll_pos
  end

  module Replace = struct
    type state = {
      sel : ll_state;
      held : string; (* input bytes [from, sel.ll_pos) awaiting a verdict *)
      from : int;
      f : match_ -> string;
    }

    let start t ~f = { sel = ll_start t; held = ""; from = 0; f }

    (* Copy [held] around the selected matches, splicing in [f m]. Bytes
       are held back only while a pending or unseen match could still
       cover them: everything before [pos - max_len + 1] (and before the
       greedy frontier) is safe to emit verbatim. *)
    let emit st held pos selected safe =
      let buf = Buffer.create (String.length held) in
      let from = ref st.from in
      List.iter
        (fun m ->
          Buffer.add_substring buf held (!from - st.from) (m.start - !from);
          Buffer.add_string buf (st.f m);
          from := m.stop)
        selected;
      let safe = max !from safe in
      Buffer.add_substring buf held (!from - st.from) (safe - !from);
      (Buffer.contents buf, String.sub held (safe - st.from) (pos - safe), safe)

    let feed t st chunk =
      let sel, selected = ll_feed t st.sel chunk in
      let held = st.held ^ chunk in
      let safe =
        if sel.ll_max = 0 then sel.ll_pos else sel.ll_pos - sel.ll_max + 1
      in
      let out, held, from = emit st held sel.ll_pos selected (max st.from safe) in
      ({ st with sel; held; from }, out)

    let flush st =
      let out, _, _ =
        emit st st.held st.sel.ll_pos (ll_flush st.sel) st.sel.ll_pos
      in
      out

    let pos st = st.sel.ll_pos
  end
end
