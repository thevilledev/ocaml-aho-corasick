(* Transitions are stored two ways. The shallowest nodes (the first
   [dense_budget] in breadth-first order, so the root and everything
   near it, where the automaton spends nearly all its time) get a full
   256-entry row holding the fully resolved next state for every byte:
   one array load per input byte, no failure links to follow. Deeper
   nodes keep only their real children, sorted by byte in one shared
   array, and fall back along failure links until a dense node answers.
   An automaton with at most [dense_budget] nodes is therefore a plain
   DFA; larger ones are a DFA near the root and an NFA further down. *)
type t = {
  dense_row : int array; (* node -> offset of its row in [dense], or -1 *)
  dense : int array; (* rows of 256 next states *)
  child_start : int array; (* node -> first child index; length nodes + 1 *)
  child_byte : int array; (* sorted within each node's range *)
  child_node : int array;
  fail : int array;
  out : int array array; (* pattern indexes ending exactly at a node *)
  dlink : int array; (* nearest proper suffix node with outputs, or -1 *)
  hit : int array; (* the node itself if it has outputs, else its dlink *)
  pat_len : int array;
  patterns : string array;
  ignore_case : bool;
  max_len : int;
}

type match_ = { pattern : int; start : int; stop : int }

(* Dense rows are 2 KiB each, so this bounds them at 8 MiB. *)
let dense_budget = 4096

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
  let children = !children and out_l = !out_l in
  let fail = Array.make n 0 in
  let dlink = Array.make n (-1) in
  let out = Array.init n (fun i -> Array.of_list (List.rev out_l.(i))) in
  (* breadth-first computation of failure and dictionary-suffix links;
     the visiting order itself is kept, shallowest nodes first *)
  let order = Array.make n 0 and visited = ref 0 in
  let q = Queue.create () in
  Queue.add 0 q;
  let rec goto s c =
    match Hashtbl.find_opt trans ((s lsl 8) lor c) with
    | Some v -> v
    | None -> if s = 0 then 0 else goto fail.(s) c
  in
  while not (Queue.is_empty q) do
    let u = Queue.pop q in
    order.(!visited) <- u;
    incr visited;
    if u <> 0 then
      dlink.(u) <-
        (if Array.length out.(fail.(u)) > 0 then fail.(u) else dlink.(fail.(u)));
    List.iter
      (fun (c, v) ->
        fail.(v) <- (if u = 0 then 0 else goto fail.(u) c);
        Queue.add v q)
      children.(u)
  done;
  let hit = Array.init n (fun i -> if Array.length out.(i) > 0 then i else dlink.(i)) in
  (* every node's children, sorted by byte, in one array *)
  let child_start = Array.make (n + 1) 0 in
  for i = 0 to n - 1 do
    child_start.(i + 1) <- child_start.(i) + List.length children.(i)
  done;
  let child_byte = Array.make child_start.(n) 0 in
  let child_node = Array.make child_start.(n) 0 in
  for i = 0 to n - 1 do
    List.iteri
      (fun j (c, v) ->
        child_byte.(child_start.(i) + j) <- c;
        child_node.(child_start.(i) + j) <- v)
      (List.sort compare children.(i))
  done;
  (* dense rows: a node's row is its failure node's row (shallower, so
     already complete) overridden by its own children; the root's row
     is the root itself except for its children *)
  let n_dense = min n dense_budget in
  let dense_row = Array.make n (-1) in
  let dense = Array.make (n_dense * 256) 0 in
  for k = 0 to n_dense - 1 do
    let u = order.(k) in
    let row = k * 256 in
    dense_row.(u) <- row;
    if u <> 0 then Array.blit dense dense_row.(fail.(u)) dense row 256;
    for j = child_start.(u) to child_start.(u + 1) - 1 do
      dense.(row + child_byte.(j)) <- child_node.(j)
    done
  done;
  let pat_len = Array.map String.length patterns in
  {
    dense_row;
    dense;
    child_start;
    child_byte;
    child_node;
    fail;
    out;
    dlink;
    hit;
    pat_len;
    patterns;
    ignore_case;
    max_len = Array.fold_left max 0 pat_len;
  }

let pattern_count t = Array.length t.patterns

let pattern t i =
  if i < 0 || i >= Array.length t.patterns then
    invalid_arg "Aho_corasick.pattern: index out of bounds";
  t.patterns.(i)

let byte t s i =
  let c = Char.code (String.unsafe_get s i) in
  if t.ignore_case && c >= 0x41 && c <= 0x5a then c + 0x20 else c

(* The child of a sparse node for byte [c], or -1. Node ids, byte values
   and child ranges all come from [build], so the unchecked accesses in
   this and the following functions stay in bounds. *)
let find_child t lo hi c =
  if hi - lo <= 8 then begin
    let rec linear i =
      if i >= hi then -1
      else
        let b = Array.unsafe_get t.child_byte i in
        if b = c then Array.unsafe_get t.child_node i
        else if b > c then -1
        else linear (i + 1)
    in
    linear lo
  end
  else begin
    let rec binary lo hi =
      if lo >= hi then -1
      else
        let mid = (lo + hi) lsr 1 in
        let b = Array.unsafe_get t.child_byte mid in
        if b = c then Array.unsafe_get t.child_node mid
        else if b < c then binary (mid + 1) hi
        else binary lo mid
    in
    binary lo hi
  end

let step t s c =
  let rec go s =
    let row = Array.unsafe_get t.dense_row s in
    if row >= 0 then Array.unsafe_get t.dense (row + c)
    else
      let v =
        find_child t
          (Array.unsafe_get t.child_start s)
          (Array.unsafe_get t.child_start (s + 1))
          c
      in
      if v >= 0 then v else go (Array.unsafe_get t.fail s)
  in
  go s

(* Prepend a match_ for every pattern ending at [node] (own outputs,
   then the dictionary-suffix chain) onto [acc]. [stop] is absolute. *)
let prepend_matches t node stop acc =
  let acc = ref acc in
  let d = ref (Array.unsafe_get t.hit node) in
  while !d >= 0 do
    let outs = Array.unsafe_get t.out !d in
    for i = 0 to Array.length outs - 1 do
      let p = Array.unsafe_get outs i in
      acc := { pattern = p; start = stop - Array.unsafe_get t.pat_len p; stop } :: !acc
    done;
    d := Array.unsafe_get t.dlink !d
  done;
  !acc

let scan t ?(node = 0) ?(base = 0) s =
  let acc = ref [] and st = ref node in
  for i = 0 to String.length s - 1 do
    let n = step t !st (byte t s i) in
    st := n;
    if Array.unsafe_get t.hit n >= 0 then
      acc := prepend_matches t n (base + i + 1) !acc
  done;
  (!st, List.rev !acc)

let find_all t s = snd (scan t s)

let find_iter t s =
  let n = String.length s in
  let rec next i node pending () =
    match pending with
    | m :: rest -> Seq.Cons (m, next i node rest)
    | [] ->
      (* consume input up to the next byte at which something matches *)
      let i = ref i and node = ref node and found = ref false in
      while (not !found) && !i < n do
        node := step t !node (byte t s !i);
        incr i;
        if Array.unsafe_get t.hit !node >= 0 then found := true
      done;
      if !found then next !i !node (List.rev (prepend_matches t !node !i [])) ()
      else Seq.Nil
  in
  next 0 0 []

(* Leftmost-longest selection. The greedy rule -- walk the starts in
   increasing order, take the longest match beginning at each start that
   lies at or after the end of the last match taken -- needs only the
   best match per start. A match ending at position [stop] starts at or
   after [stop - max_len], so a start is final once scanning is
   [max_len] bytes past it: the undecided starts fit a window of
   [max_len + 1] slots indexed by start modulo the size (no two live
   starts share a slot), and the whole selection is one pass over the
   input with no sorting and nothing materialised but the result. *)
type window = {
  wlen : int array; (* longest match starting at slot's start, or 0 *)
  wpat : int array; (* its pattern *)
  wsize : int; (* max_len + 1; a start lives in slot [start mod wsize] *)
}

let window t candidates =
  let wsize = t.max_len + 1 in
  let wd = { wlen = Array.make wsize 0; wpat = Array.make wsize 0; wsize } in
  List.iter
    (fun m ->
      let slot = m.start mod wsize in
      wd.wlen.(slot) <- m.stop - m.start;
      wd.wpat.(slot) <- m.pattern)
    candidates;
  wd

(* Scan [s], whose first byte is at absolute offset [base], from [node]:
   record the matches into the window (longest per start, and among
   duplicates the first listed, which is the order they arrive in) and
   select, in start order, each start as it becomes final. [cursor] is
   the end of the last selected match. Returns the final node and cursor
   and the selected matches prepended to [acc]. *)
let window_scan t wd node base s cursor acc =
  let node = ref node and cursor = ref cursor and acc = ref acc in
  for i = 0 to String.length s - 1 do
    let nd = step t !node (byte t s i) in
    node := nd;
    let stop = base + i + 1 in
    let d = ref (Array.unsafe_get t.hit nd) in
    while !d >= 0 do
      let outs = Array.unsafe_get t.out !d in
      for k = 0 to Array.length outs - 1 do
        let p = Array.unsafe_get outs k in
        let len = Array.unsafe_get t.pat_len p in
        let slot = (stop - len) mod wd.wsize in
        if len > Array.unsafe_get wd.wlen slot then begin
          Array.unsafe_set wd.wlen slot len;
          Array.unsafe_set wd.wpat slot p
        end
      done;
      d := Array.unsafe_get t.dlink !d
    done;
    (* the start [max_len] bytes back can receive no more matches: any
       later match ends later and is at most [max_len] long *)
    if stop >= t.max_len then begin
      let start = stop - t.max_len in
      let slot = start mod wd.wsize in
      let len = Array.unsafe_get wd.wlen slot in
      if len > 0 then begin
        Array.unsafe_set wd.wlen slot 0;
        if start >= !cursor then begin
          acc :=
            { pattern = Array.unsafe_get wd.wpat slot; start; stop = start + len }
            :: !acc;
          cursor := start + len
        end
      end
    end
  done;
  (!node, !cursor, !acc)

(* The candidates still undecided at absolute position [pos] -- starts
   less than [max_len] bytes back -- in start order, minus those a
   selected match already covers. *)
let window_rest t wd pos cursor =
  let rest = ref [] in
  for start = pos - 1 downto max cursor (pos - t.max_len + 1) do
    let slot = start mod wd.wsize in
    let len = Array.unsafe_get wd.wlen slot in
    if len > 0 then
      rest := { pattern = Array.unsafe_get wd.wpat slot; start; stop = start + len } :: !rest
  done;
  !rest

(* Greedy selection over candidates in start order. *)
let select cursor acc candidates =
  List.fold_left
    (fun (cursor, acc) m ->
      if m.start >= cursor then (m.stop, m :: acc) else (cursor, acc))
    (cursor, acc) candidates

let find_leftmost_longest t s =
  let wd = window t [] in
  let _, cursor, acc = window_scan t wd 0 0 s 0 [] in
  let _, acc = select cursor acc (window_rest t wd (String.length s) cursor) in
  List.rev acc

let mem t s =
  let n = String.length s in
  let rec go i node =
    if i >= n then false
    else begin
      let node = step t node (byte t s i) in
      Array.unsafe_get t.hit node >= 0 || go (i + 1) node
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

  (* The single match the automaton sees first ending at a position is
     the longest one (a node's own outputs precede its dictionary-suffix
     chain, and [dlink] points at the deepest suffix with outputs). *)
  let feed_nonoverlapping t st chunk =
    let node = ref st.node and acc = ref [] in
    for i = 0 to String.length chunk - 1 do
      let n = step t !node (byte t chunk i) in
      let h = Array.unsafe_get t.hit n in
      if h >= 0 then begin
        let p = Array.unsafe_get (Array.unsafe_get t.out h) 0 in
        let stop = st.pos + i + 1 in
        acc := { pattern = p; start = stop - Array.unsafe_get t.pat_len p; stop } :: !acc;
        node := 0
      end
      else node := n
    done;
    ({ node = !node; pos = st.pos + String.length chunk }, List.rev !acc)

  let pos st = st.pos

  (* Leftmost-longest cannot always decide a match the moment it ends: a
     longer match starting at or before it may still be in progress. But
     no match exceeds the longest pattern, so once scanning is [max_len]
     bytes past a candidate's start nothing can outrank it. This is the
     one pass of {!find_leftmost_longest}, cut at chunk boundaries: the
     undecided window -- at most one candidate per start, at most
     [max_len] of them -- is carried between feeds as a list. *)
  type ll_state = {
    ll_node : int;
    ll_pos : int;
    ll_done : int; (* end of the last selected match *)
    ll_pending : match_ list; (* best match per undecided start, in start order *)
    ll_max : int; (* longest pattern length *)
  }

  let ll_start t =
    { ll_node = 0; ll_pos = 0; ll_done = 0; ll_pending = []; ll_max = t.max_len }

  let ll_feed t st chunk =
    let wd = window t st.ll_pending in
    let node, cursor, acc = window_scan t wd st.ll_node st.ll_pos chunk st.ll_done [] in
    let pos = st.ll_pos + String.length chunk in
    ( { st with ll_node = node; ll_pos = pos; ll_done = cursor;
        ll_pending = window_rest t wd pos cursor },
      List.rev acc )

  let ll_flush st =
    let _, acc = select st.ll_done [] st.ll_pending in
    List.rev acc

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
