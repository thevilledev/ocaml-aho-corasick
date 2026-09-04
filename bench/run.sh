#!/usr/bin/env bash
# Run every implementation over every workload and search mode, then
# render the report. See README.md.
#
#   SECONDS_PER_RUN=2 ./bench/run.sh          # results in bench/_out/
#   WORKLOADS=workloads-smoke.tsv ./bench/run.sh
#
# Needs: dune (run under `opam exec --` if needed), cargo, python3, curl;
# pyahocorasick and ahocorasick_rs are used when importable.
set -euo pipefail
cd "$(dirname "$0")"

SECONDS_PER_RUN="${SECONDS_PER_RUN:-2}"
WORKLOADS="${WORKLOADS:-workloads.tsv}"
OUT="${OUT:-_out}"

./fetch-corpora.sh
(cd .. && dune build compat/ocaml/driver.exe)
(cd ../compat/rust && cargo build --release --quiet)

OCAML=../_build/default/compat/ocaml/driver.exe
RUST=../compat/rust/target/release/aho-corasick-compat
PYTHON=../compat/python/driver.py
have_pyahocorasick=$(python3 -c 'import ahocorasick' 2>/dev/null && echo yes || echo no)
have_ahocorasick_rs=$(python3 -c 'import ahocorasick_rs' 2>/dev/null && echo yes || echo no)

mkdir -p "$OUT"
results="$OUT/results.tsv"
: > "$results"
{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "cpu: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || uname -m) x$(nproc 2>/dev/null || echo ?)"
  echo "os: $(uname -srm)"
  echo "ocaml: $(ocamlfind ocamlopt -version 2>/dev/null || ocamlopt -version)"
  echo "rust: $(rustc --version) / aho-corasick $(grep -A1 'name = "aho-corasick"' ../compat/rust/Cargo.lock | grep version | cut -d'"' -f2)"
  echo "python: $(python3 --version | cut -d' ' -f2)"
  [ "$have_pyahocorasick" = yes ] && echo "pyahocorasick: $(python3 -c 'import importlib.metadata as m; print(m.version("pyahocorasick"))')"
  [ "$have_ahocorasick_rs" = yes ] && echo "ahocorasick_rs: $(python3 -c 'import importlib.metadata as m; print(m.version("ahocorasick_rs"))')"
  echo "seconds per measurement: $SECONDS_PER_RUN"
} > "$OUT/env.txt"
cat "$OUT/env.txt"

run() { # <workload> <command...>: append "<workload>\t<driver's result line>"
  local workload=$1
  shift
  printf '%s\t' "$workload" >> "$results"
  "$@" >> "$results"
}

wants() { # <engines column> <engine>
  [ "$1" = all ] || [[ ",$1," == *",$2,"* ]]
}

while IFS=$'\t' read -r name patterns haystack expected engines; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  echo "== $name"
  if wants "$engines" ocaml; then
    for mode in overlapping overlapping_iter standard leftmost_longest is_match replace \
                standard_stream overlapping_stream leftmost_longest_stream; do
      run "$name" "$OCAML" bench "$mode" "$patterns" "$haystack" --seconds "$SECONDS_PER_RUN"
    done
  fi
  if wants "$engines" rust; then
    for mode in overlapping standard leftmost_longest is_match replace standard_stream; do
      run "$name" "$RUST" bench "$mode" "$patterns" "$haystack" --seconds "$SECONDS_PER_RUN"
    done
    for mode in overlapping standard leftmost_longest; do
      run "$name" "$RUST" bench "$mode" "$patterns" "$haystack" --seconds "$SECONDS_PER_RUN" --engine nfa
    done
  fi
  if wants "$engines" python; then
    if [ "$have_pyahocorasick" = yes ]; then
      for mode in overlapping iter_long is_match; do
        run "$name" python3 "$PYTHON" bench "$mode" "$patterns" "$haystack" --lib pyahocorasick --seconds "$SECONDS_PER_RUN"
      done
    fi
    if [ "$have_ahocorasick_rs" = yes ]; then
      for mode in overlapping standard leftmost_longest; do
        run "$name" python3 "$PYTHON" bench "$mode" "$patterns" "$haystack" --lib ahocorasick_rs --seconds "$SECONDS_PER_RUN"
      done
    fi
  fi
done < "$WORKLOADS"

python3 report.py "$results" --workloads "$WORKLOADS" --env "$OUT/env.txt" | tee "$OUT/report.md"
