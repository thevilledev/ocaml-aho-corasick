#!/usr/bin/env python3
"""Compare a subject driver's results against an oracle driver's results.

  compare.py --cases cases.tsv --subject ocaml.tsv --oracle rust.tsv --name "rust aho-corasick"

Results are compared per (case, mode). `--map SUBJECT_MODE=ORACLE_MODE`
compares a subject mode against a differently named oracle mode (a
streamed mode against the oracle's whole-input mode, say). For modes
whose result is a match list, a result with the same matches in a
different order is counted separately ("same set"); it fails the run
unless `--allow-order` is given. `--soft MODE` reports disagreements in
a subject mode without failing on them.

Exit status 0 when every compared result agrees, 1 otherwise, 2 when
nothing could be compared. See README.md for the formats.
"""

import argparse
import sys
from collections import Counter, defaultdict

MATCH_MODES = {
    "overlapping",
    "overlapping_stream",
    "standard",
    "standard_stream",
    "leftmost_longest",
    "leftmost_longest_stream",
    "first",
    "first_leftmost_longest",
    "iter_long",
}


def load_results(path):
    results = {}
    with open(path, encoding="ascii") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            id_, mode, value = line.split("\t", 2)
            results[(id_, mode)] = value
    return results


def load_cases(path):
    cases = {}
    with open(path, encoding="ascii") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            id_, flags, patterns, input_, chunks = line.split("\t")
            cases[id_] = (
                flags,
                [bytes.fromhex(p) for p in patterns.split(",")] if patterns else [],
                bytes.fromhex(input_),
                chunks,
            )
    return cases


def parse_matches(value):
    if value == "-":
        return []
    return [tuple(int(x) for x in m.split(":")) for m in value.split(" ")]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cases", required=True)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--oracle", required=True)
    parser.add_argument("--name", required=True, help="the oracle's name, for the report")
    parser.add_argument("--map", action="append", default=[], metavar="SUBJECT_MODE=ORACLE_MODE")
    parser.add_argument("--allow-order", action="store_true")
    parser.add_argument("--soft", action="append", default=[], metavar="MODE")
    parser.add_argument("--show", type=int, default=5, help="disagreements to print per mode")
    args = parser.parse_args()

    mapping = dict(m.split("=", 1) for m in args.map)
    subject = load_results(args.subject)
    oracle = load_results(args.oracle)
    cases = load_cases(args.cases)

    stats = defaultdict(Counter)
    examples = defaultdict(list)
    for (id_, smode), svalue in subject.items():
        omode = mapping.get(smode, smode)
        ovalue = oracle.get((id_, omode))
        if ovalue is None:
            continue
        counter = stats[smode]
        counter["compared"] += 1
        if svalue == ovalue:
            counter["identical"] += 1
            continue
        if smode in MATCH_MODES and sorted(parse_matches(svalue)) == sorted(parse_matches(ovalue)):
            kind = "same set, different order"
            counter["order"] += 1
        else:
            kind = "disagreement"
            counter["mismatch"] += 1
        if len(examples[smode]) < args.show:
            examples[smode].append((kind, id_, omode, svalue, ovalue))

    if not stats:
        print(f"{args.name}: nothing compared", file=sys.stderr)
        return 2

    failed = False
    print(f"subject vs {args.name}: {len(cases)} cases")
    print(f"  {'subject mode':<25} {'oracle mode':<18} {'compared':>8} {'identical':>9} {'same set':>8} {'differ':>6}")
    for smode in sorted(stats):
        counter = stats[smode]
        print(
            f"  {smode:<25} {mapping.get(smode, smode):<18} {counter['compared']:>8} "
            f"{counter['identical']:>9} {counter['order']:>8} {counter['mismatch']:>6}"
        )
        bad = counter["mismatch"] + (0 if args.allow_order else counter["order"])
        if bad and smode not in args.soft:
            failed = True
    for smode in sorted(examples):
        for kind, id_, omode, svalue, ovalue in examples[smode]:
            flags, patterns, input_, chunks = cases[id_]
            print(
                f"\n{kind}: case {id_}, subject {smode} vs {args.name} {omode}\n"
                f"  flags={flags} chunks=[{chunks}]\n"
                f"  patterns={patterns!r}\n"
                f"  input={input_!r}\n"
                f"  subject: {svalue}\n"
                f"  oracle:  {ovalue}"
            )
    print("FAILED" if failed else "OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
