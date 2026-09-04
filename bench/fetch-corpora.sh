#!/usr/bin/env bash
# Fetch the benchmark corpora into bench/corpora/ and verify their checksums.
#
# The real-text corpora and word lists are the ones the Rust aho-corasick
# crate's rebar benchmark suite uses, pinned to a commit so that the match
# counts recorded there (bench/workloads.tsv) apply to exactly these bytes:
# sherlock.txt is Project Gutenberg's The Adventures of Sherlock Holmes,
# en-sampled.txt a sample of the OpenSubtitles 2018 English corpus, and the
# word lists are English dictionary excerpts. The synthetic corpora are
# generated deterministically by synth.py.
set -euo pipefail
cd "$(dirname "$0")"

COMMIT=6c0abf5681bfc30bb9d8f7f52b68a350b436fffa
BASE="https://raw.githubusercontent.com/BurntSushi/aho-corasick/$COMMIT/benchmarks"
mkdir -p corpora

fetch() { # <path under benchmarks/> <sha256> <local name>
  local path=$1 sum=$2 dest="corpora/$3"
  if [ ! -f "$dest" ]; then
    echo "fetching $path"
    curl -sSfL "$BASE/$path" -o "$dest.tmp"
    mv "$dest.tmp" "$dest"
  fi
  echo "$sum  $dest" | sha256sum --check --quiet
}

fetch haystacks/sherlock.txt \
  a31a2125347e4daf528cc95b73d1776defd0957b2f1e3463a543de3d49266e4d sherlock.txt
fetch haystacks/opensubtitles/en-sampled.txt \
  0d40805f6d02c8fe02bd75945b98911891f707e8ecb939e018446858065d76ea en-sampled.txt
fetch regexes/words-5000 \
  37f2e93f85ed84a7a1612e1d172ee8df7af56a8a6bef0728ed6f390c307f3414 words-5000
fetch regexes/words-15000 \
  2aa4a35f6d76c440d90221b85ef2d0e9f35ae2943b233f615525be9074a71272 words-15000
fetch regexes/dictionary/english/length-15.txt \
  8e5c78a5b7db76cfd0bca99157cdb7088b379aee9aa34508de0cc9cb42c274e7 dictionary-length-15.txt

python3 synth.py corpora
