#!/usr/bin/env python3
"""Differential-test and benchmark driver for the Python Aho-Corasick
libraries: pyahocorasick (an independent C implementation) and, when it
is installed, ahocorasick_rs (a binding to the Rust crate).

  driver.py cases --lib pyahocorasick < cases.tsv
  driver.py bench <mode> <patterns-file> <haystack-file> --lib pyahocorasick

The case and result formats are described in ../README.md. The Rust and
OCaml drivers speak the same formats.

Neither library folds case, so for cases flagged `i` this driver lowers
both the patterns and the input with bytes.lower(), which folds exactly
the ASCII letters and nothing else -- the same folding the OCaml and
Rust libraries apply.
"""

import argparse
import sys
import time


def parse_case(line):
    if not line or line.startswith("#"):
        return None
    fields = line.split("\t")
    if len(fields) != 5:
        raise SystemExit(f"malformed case line: {line!r}")
    id_, flags, patterns, input_, chunks = fields
    return {
        "id": id_,
        "ignore_case": "i" in flags,
        "patterns": [bytes.fromhex(p) for p in patterns.split(",")] if patterns else [],
        "input": bytes.fromhex(input_),
        "chunks": [int(n) for n in chunks.split(",")] if chunks else [],
    }


def fmt_matches(matches):
    return "-" if not matches else " ".join(f"{p}:{s}:{e}" for p, s, e in matches)


def fold(data, ignore_case):
    return data.lower() if ignore_case else data


class PyAhoCorasick:
    """pyahocorasick. Keys are the bytes decoded as Latin-1, so one
    character is one byte and the reported indices are byte offsets.
    Duplicate patterns share a key; the value is the list of their
    indices. iter() reports an inclusive end index, converted here to
    the half-open convention."""

    name = "pyahocorasick"

    def __init__(self, patterns, ignore_case):
        import ahocorasick

        self.ignore_case = ignore_case
        self.lengths = [len(p) for p in patterns]
        self.automaton = ahocorasick.Automaton()
        for i, p in enumerate(patterns):
            key = fold(p, ignore_case).decode("latin-1")
            if self.automaton.exists(key):
                self.automaton.get(key).append(i)
            else:
                self.automaton.add_word(key, [i])
        self.empty = not patterns
        if not self.empty:
            self.automaton.make_automaton()

    def text(self, data):
        return fold(data, self.ignore_case).decode("latin-1")

    def expand(self, hits, all_duplicates):
        out = []
        for end, ids in hits:
            for i in ids if all_duplicates else ids[:1]:
                out.append((i, end + 1 - self.lengths[i], end + 1))
        return out

    def overlapping(self, data):
        """Every index of a duplicated pattern is a distinct match."""
        return [] if self.empty else self.expand(self.automaton.iter(self.text(data)), True)

    def iter_long(self, data):
        """A non-overlapping search reports one match per position: for a
        duplicated pattern, the lowest index, as the other libraries do."""
        return [] if self.empty else self.expand(self.automaton.iter_long(self.text(data)), False)

    def modes(self, case):
        data = case["input"]
        overlapping = self.overlapping(data)
        yield "overlapping", fmt_matches(overlapping)
        yield "iter_long", fmt_matches(self.iter_long(data))
        yield "is_match", "true" if overlapping else "false"
        yield "first", fmt_matches(overlapping[:1])

    def bench(self, mode, data):
        text = self.text(data)
        if mode == "overlapping":
            return sum(1 for _ in self.automaton.iter(text))
        if mode == "iter_long":
            return sum(1 for _ in self.automaton.iter_long(text))
        if mode == "is_match":
            return 1 if next(self.automaton.iter(text), None) is not None else 0
        raise SystemExit(f"unsupported bench mode for pyahocorasick: {mode}")


class AhoCorasickRs:
    """ahocorasick_rs, through its BytesAhoCorasick class, which reports
    byte offsets."""

    name = "ahocorasick_rs"

    def __init__(self, patterns, ignore_case):
        import ahocorasick_rs as rs

        self.ignore_case = ignore_case
        folded = [fold(p, ignore_case) for p in patterns]
        self.standard = rs.BytesAhoCorasick(folded)
        self.longest = rs.BytesAhoCorasick(folded, matchkind=rs.MatchKind.LeftmostLongest)

    def text(self, data):
        return fold(data, self.ignore_case)

    def modes(self, case):
        text = self.text(case["input"])
        standard = self.standard.find_matches_as_indexes(text)
        yield "overlapping", fmt_matches(self.standard.find_matches_as_indexes(text, overlapping=True))
        yield "standard", fmt_matches(standard)
        yield "leftmost_longest", fmt_matches(self.longest.find_matches_as_indexes(text))
        yield "is_match", "true" if standard else "false"
        yield "first", fmt_matches(standard[:1])

    def bench(self, mode, data):
        text = self.text(data)
        if mode == "overlapping":
            return len(self.standard.find_matches_as_indexes(text, overlapping=True))
        if mode == "standard":
            return len(self.standard.find_matches_as_indexes(text))
        if mode == "leftmost_longest":
            return len(self.longest.find_matches_as_indexes(text))
        raise SystemExit(f"unsupported bench mode for ahocorasick_rs: {mode}")


LIBS = {"pyahocorasick": PyAhoCorasick, "ahocorasick_rs": AhoCorasickRs}


def run_cases(lib):
    out = sys.stdout
    for line in sys.stdin:
        case = parse_case(line.rstrip("\n"))
        if case is None:
            continue
        oracle = lib(case["patterns"], case["ignore_case"])
        for mode, result in oracle.modes(case):
            out.write(f"{case['id']}\t{mode}\t{result}\n")


def run_bench(lib, mode, patterns_file, haystack_file, seconds):
    with open(patterns_file, "rb") as f:
        patterns = [line for line in f.read().split(b"\n") if line]
    with open(haystack_file, "rb") as f:
        haystack = f.read()
    started = time.perf_counter_ns()
    oracle = lib(patterns, False)
    build_ns = time.perf_counter_ns() - started
    count = oracle.bench(mode, haystack)
    samples = []
    started = time.perf_counter()
    while time.perf_counter() - started < seconds or len(samples) < 3:
        t0 = time.perf_counter_ns()
        c = oracle.bench(mode, haystack)
        samples.append(time.perf_counter_ns() - t0)
        if c != count:
            raise SystemExit("count changed between runs")
    samples.sort()
    print(
        f"python/{lib.name}\t{mode}\t{len(haystack)}\t{len(samples)}\t{build_ns}"
        f"\t{samples[0]}\t{samples[len(samples) // 2]}\t{count}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    cases = sub.add_parser("cases")
    cases.add_argument("--lib", choices=sorted(LIBS), default="pyahocorasick")
    bench = sub.add_parser("bench")
    bench.add_argument("mode")
    bench.add_argument("patterns")
    bench.add_argument("haystack")
    bench.add_argument("--lib", choices=sorted(LIBS), default="pyahocorasick")
    bench.add_argument("--seconds", type=float, default=2.0)
    args = parser.parse_args()
    lib = LIBS[args.lib]
    if args.command == "cases":
        run_cases(lib)
    else:
        run_bench(lib, args.mode, args.patterns, args.haystack, args.seconds)


if __name__ == "__main__":
    main()
