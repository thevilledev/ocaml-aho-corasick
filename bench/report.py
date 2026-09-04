#!/usr/bin/env python3
"""Render benchmark results as Markdown (or HTML fragments) and cross-check
the match counts.

  report.py results.tsv --workloads workloads.tsv [--env env.txt] [--html]

results.tsv holds one line per measurement: workload, engine, mode,
haystack bytes, iterations, build ns, min ns, median ns, count. Every
implementation that ran a (workload, mode) must have reported the same
count, the streamed and lazy modes must agree with the modes they mirror,
and a workload with a recorded count must reproduce it; otherwise the
exit status is 1. pyahocorasick's iter_long is exempt (compat/README.md).
"""

import argparse
import html
import sys
from collections import OrderedDict, defaultdict

ENGINES = [
    ("ocaml/aho-corasick", "OCaml"),
    ("rust/aho-corasick/default", "Rust default"),
    ("rust/aho-corasick/nfa", "Rust NFA"),
    ("python/ahocorasick_rs", "ahocorasick_rs"),
    ("python/pyahocorasick", "pyahocorasick"),
]
MODES = [
    "overlapping",
    "overlapping_iter",
    "standard",
    "leftmost_longest",
    "is_match",
    "replace",
    "standard_stream",
    "overlapping_stream",
    "leftmost_longest_stream",
]
# pyahocorasick's iter_long is its leftmost-longest search.
ALIAS = {"iter_long": "leftmost_longest"}
# A streamed or lazy mode must report the same count as the mode it mirrors.
SAME_COUNT_AS = {
    "overlapping_iter": "overlapping",
    "overlapping_stream": "overlapping",
    "standard_stream": "standard",
    "leftmost_longest_stream": "leftmost_longest",
}
# Known to miss matches; reported, not enforced.
SOFT = {("python/pyahocorasick", "leftmost_longest")}


def load(path):
    rows = defaultdict(dict)
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) != 9:
                # a measurement that is still running or failed
                print(f"skipping incomplete line: {line!r}", file=sys.stderr)
                continue
            workload, engine, mode, nbytes, iters, build_ns, min_ns, median_ns, count = fields
            mode = ALIAS.get(mode, mode)
            rows[(workload, mode)][engine] = {
                "bytes": int(nbytes),
                "iters": int(iters),
                "build_ns": int(build_ns),
                "min_ns": int(min_ns),
                "median_ns": int(median_ns),
                "count": int(count),
            }
    return rows


def load_workloads(path):
    workloads = OrderedDict()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            name, _patterns, _haystack, expected, _engines = line.split("\t")
            workloads[name] = None if expected == "-" else int(expected)
    return workloads


def fmt_rate(r):
    if r["median_ns"] == 0:
        return "early exit"  # below the timer's resolution
    mbps = r["bytes"] / r["median_ns"] * 1e3
    return f"{mbps:,.0f}" if mbps >= 100 else f"{mbps:.1f}"


class Table:
    def __init__(self, caption, header, numeric):
        self.caption, self.header, self.numeric, self.rows = caption, header, numeric, []

    def markdown(self):
        out = [f"### {self.caption}", "", "| " + " | ".join(self.header) + " |"]
        out.append("|" + "|".join("---:" if n else "---" for n in self.numeric) + "|")
        for row in self.rows:
            out.append("| " + " | ".join(row) + " |")
        return "\n".join(out) + "\n"

    def html(self):
        out = ['<div class="table-scroll">', "  <table>", f"    <caption>{html.escape(self.caption)}</caption>", "    <thead>", "      <tr>"]
        for h, n in zip(self.header, self.numeric):
            cls = ' class="n"' if n else ""
            out.append(f'        <th scope="col"{cls}>{html.escape(h)}</th>')
        out += ["      </tr>", "    </thead>", "    <tbody>"]
        for row in self.rows:
            out.append("      <tr>")
            for cell, n in zip(row, self.numeric):
                cls = ' class="n"' if n else ""
                out.append(f"        <td{cls}>{html.escape(cell)}</td>")
            out.append("      </tr>")
        out += ["    </tbody>", "  </table>", "</div>"]
        return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("results")
    parser.add_argument("--workloads", required=True)
    parser.add_argument("--env")
    parser.add_argument("--html", action="store_true", help="emit HTML table fragments instead of Markdown")
    args = parser.parse_args()
    rows = load(args.results)
    workloads = load_workloads(args.workloads)
    engines = [(e, label) for e, label in ENGINES if any(e in r for r in rows.values())]
    labels = dict(engines)
    problems = []
    tables = []

    throughput = Table(
        "Throughput, MB/s, median over runs (bigger is better)",
        ["workload", "mode"] + [label for _, label in engines] + ["matches"],
        [False, False] + [True] * len(engines) + [True],
    )
    counts = {}
    for name in workloads:
        for mode in MODES:
            row = rows.get((name, mode))
            if not row:
                continue
            strict = {e: r["count"] for e, r in row.items() if (e, mode) not in SOFT}
            distinct = sorted(set(strict.values()))
            if len(distinct) == 1:
                count = distinct[0]
                counts[(name, mode)] = count
                text = f"{count:,}"
            else:
                text = "DISAGREE " + " / ".join(f"{labels[e]} {row[e]['count']:,}" for e in strict)
                problems.append(f"{name} {mode}: implementations disagree on the count: {text}")
            for e, r in row.items():
                if (e, mode) in SOFT and (not distinct or r["count"] != distinct[0]):
                    text += f" ({labels[e]}: {r['count']:,})"
            if mode == "is_match" and distinct == [1]:
                # a hit ends the scan early: the rate says nothing
                cells = ["early exit" if e in row else "" for e, _ in engines]
                text = "found"
            else:
                cells = [fmt_rate(row[e]) if e in row else "" for e, _ in engines]
            throughput.rows.append([name, mode] + cells + [text])
    tables.append(throughput)

    for (name, mode), count in counts.items():
        base = SAME_COUNT_AS.get(mode)
        if base and (name, base) in counts and counts[(name, base)] != count:
            problems.append(f"{name} {mode}: count {count:,} differs from {base}: {counts[(name, base)]:,}")

    recorded = Table(
        "Counts rebar records for the Rust crate on the same bytes, against the standard-mode count measured here",
        ["workload", "recorded", "measured", "result"],
        [False, True, True, False],
    )
    for name, expected in workloads.items():
        if expected is None:
            continue
        measured = counts.get((name, "standard"))
        ok = measured == expected
        if not ok:
            problems.append(f"{name}: recorded count {expected:,}, measured {measured}")
        recorded.rows.append([name, f"{expected:,}", "" if measured is None else f"{measured:,}", "reproduced" if ok else "MISMATCH"])
    tables.append(recorded)

    build = Table("Automaton construction, ms", ["workload"] + [label for _, label in engines], [False] + [True] * len(engines))
    for name in workloads:
        cells = []
        for e, _ in engines:
            ns = next((rows[(name, m)][e]["build_ns"] for m in MODES if (name, m) in rows and e in rows[(name, m)]), None)
            cells.append("" if ns is None else f"{ns / 1e6:.2f}")
        if any(cells):
            build.rows.append([name] + cells)
    tables.append(build)

    scaling_names = [name for name in workloads if name.startswith("scaling/")]
    if scaling_names:
        cols = [(e, m) for e, _ in engines[:2] for m in ("overlapping", "standard", "leftmost_longest")]
        scaling = Table(
            "Scaling: ns per byte at growing input sizes (flat means linear time)",
            ["workload", "bytes"] + [f"{labels[e]} {m}" for e, m in cols],
            [False, True] + [True] * len(cols),
        )
        for name in scaling_names:
            first = next(iter(rows[(name, "standard")].values()))
            cells = []
            for e, m in cols:
                r = rows.get((name, m), {}).get(e)
                cells.append("" if r is None else f"{r['median_ns'] / r['bytes']:.2f}")
            scaling.rows.append([name, f"{first['bytes']:,}"] + cells)
        tables.append(scaling)

    env = []
    if args.env:
        with open(args.env, encoding="utf-8") as f:
            env = [line.rstrip() for line in f if line.strip()]

    if args.html:
        print("<!-- generated by bench/report.py -->")
        if env:
            print("<ul>")
            for line in env:
                print(f"  <li>{html.escape(line)}</li>")
            print("</ul>")
        for table in tables:
            print(table.html())
    else:
        print("# Benchmark results\n")
        for line in env:
            print(f"- {line}")
        print()
        for table in tables:
            print(table.markdown())

    if problems:
        print("## Problems\n" if not args.html else "<!-- PROBLEMS -->")
        for p in problems:
            print(f"- {p}")
        return 1
    summary = f"All {len(counts)} counts agree between implementations; recorded counts reproduced."
    print(summary if not args.html else f"<!-- {summary} -->")
    return 0


if __name__ == "__main__":
    sys.exit(main())
