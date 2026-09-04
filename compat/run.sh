#!/usr/bin/env bash
# Differential test: this library against the Rust aho-corasick crate and
# pyahocorasick (and ahocorasick_rs when it is installed), on the fixed
# vectors plus $COUNT generated cases. See README.md.
#
# Needs: dune (run under `opam exec --` if needed), cargo, python3 with
# pyahocorasick installed.
set -euo pipefail
cd "$(dirname "$0")"

SEED="${SEED:-20260904}"
COUNT="${COUNT:-20000}"
OUT="${OUT:-_out}"
mkdir -p "$OUT"

echo "== generating $COUNT cases (seed $SEED)"
python3 cases.py --seed "$SEED" --count "$COUNT" > "$OUT/cases.tsv"

echo "== building drivers"
(cd .. && dune build compat/ocaml/driver.exe)
(cd rust && cargo build --release --quiet)

echo "== running drivers"
../_build/default/compat/ocaml/driver.exe cases < "$OUT/cases.tsv" > "$OUT/ocaml.tsv"
rust/target/release/aho-corasick-compat cases < "$OUT/cases.tsv" > "$OUT/rust.tsv"
python3 python/driver.py cases --lib pyahocorasick < "$OUT/cases.tsv" > "$OUT/pyahocorasick.tsv"

status=0
echo
# Rust: every mode is specified on both sides, so results must be
# identical, order included. The streamed modes have no Rust
# counterpart and are held to Rust's whole-input answer.
python3 compare.py --cases "$OUT/cases.tsv" --subject "$OUT/ocaml.tsv" \
  --oracle "$OUT/rust.tsv" --name "rust aho-corasick" \
  --map overlapping_stream=overlapping \
  --map leftmost_longest_stream=leftmost_longest \
  --map replace_stream=replace || status=1
echo
# pyahocorasick: iter() is the overlapping search and makes no promise
# about order. iter_long() is compared against leftmost-longest but only
# reported on, because pyahocorasick 2.3.1 misses matches there: it does
# not consult the failure chain at end of input (patterns abc, b; input
# ab: b at 1..2 is not reported) nor terminal nodes more than one failure
# link away on a mismatch (patterns abcd, bcx, c; input abcz: c at 2..3).
# Every disagreement the harness has found is one of those two; see
# README.md.
python3 compare.py --cases "$OUT/cases.tsv" --subject "$OUT/ocaml.tsv" \
  --oracle "$OUT/pyahocorasick.tsv" --name pyahocorasick \
  --map overlapping_stream=overlapping \
  --map leftmost_longest=iter_long \
  --map leftmost_longest_stream=iter_long \
  --soft leftmost_longest --soft leftmost_longest_stream \
  --allow-order || status=1

if python3 -c 'import ahocorasick_rs' 2>/dev/null; then
  echo
  python3 python/driver.py cases --lib ahocorasick_rs < "$OUT/cases.tsv" > "$OUT/ahocorasick_rs.tsv"
  python3 compare.py --cases "$OUT/cases.tsv" --subject "$OUT/ocaml.tsv" \
    --oracle "$OUT/ahocorasick_rs.tsv" --name ahocorasick_rs \
    --map overlapping_stream=overlapping \
    --map leftmost_longest_stream=leftmost_longest || status=1
fi

exit $status
