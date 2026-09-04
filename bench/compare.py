#!/usr/bin/env python3
"""Compare two results files from bench/run.sh for one engine.

  compare.py before/results.tsv after/results.tsv [--engine ocaml/aho-corasick] [--html]

Prints, per workload and mode measured in both files, the throughput
before and after and the ratio, so a change to the library can be
judged on the same workloads it was measured on.
"""

import argparse
import html
import sys
from collections import OrderedDict


def load(path, engine):
    rows = OrderedDict()
    with open(path, encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 9 or fields[1] != engine:
                continue
            workload, _engine, mode, nbytes, _iters, _build, _min, median, count = fields
            if int(median) == 0:
                continue  # below the timer's resolution: an early exit
            rows[(workload, mode)] = (int(nbytes) / int(median) * 1e3, int(count))
    return rows


def fmt(x):
    return f"{x:,.0f}" if x >= 100 else f"{x:.1f}"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--engine", default="ocaml/aho-corasick")
    parser.add_argument("--html", action="store_true")
    parser.add_argument("--modes", default="", help="comma-separated modes to keep (default: all)")
    parser.add_argument("--workloads", default="", help="comma-separated workloads to keep (default: all)")
    args = parser.parse_args()
    before, after = load(args.before, args.engine), load(args.after, args.engine)
    modes = set(args.modes.split(",")) if args.modes else None
    workloads = set(args.workloads.split(",")) if args.workloads else None
    table = []
    for key, (b, bc) in before.items():
        if key not in after:
            continue
        workload, mode = key
        if modes and mode not in modes or workloads and workload not in workloads:
            continue
        a, ac = after[key]
        if bc != ac:
            print(f"count changed for {workload} {mode}: {bc} -> {ac}", file=sys.stderr)
        table.append((workload, mode, b, a))
    header = ["workload", "mode", "before, MB/s", "after, MB/s", "ratio"]
    if args.html:
        print('<div class="table-scroll">\n  <table>\n    <caption>Throughput before and after, MB/s</caption>\n    <thead>\n      <tr>')
        for i, h in enumerate(header):
            cls = ' class="n"' if i >= 2 else ""
            print(f'        <th scope="col"{cls}>{html.escape(h)}</th>')
        print("      </tr>\n    </thead>\n    <tbody>")
        for workload, mode, b, a in table:
            print(f'      <tr>\n        <td>{html.escape(workload)}</td>\n        <td>{html.escape(mode)}</td>\n        <td class="n">{fmt(b)}</td>\n        <td class="n">{fmt(a)}</td>\n        <td class="n">{a / b:.1f}x</td>\n      </tr>')
        print("    </tbody>\n  </table>\n</div>")
    else:
        print("| " + " | ".join(header) + " |")
        print("|---|---|---:|---:|---:|")
        for workload, mode, b, a in table:
            print(f"| {workload} | {mode} | {fmt(b)} | {fmt(a)} | {a / b:.1f}x |")


if __name__ == "__main__":
    main()
