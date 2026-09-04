#!/usr/bin/env python3
"""Generate differential-test cases.

  cases.py --seed 20260904 --count 20000 > cases.tsv

One case per line, tab-separated: id, flags (`-` or `i` for ASCII
case-insensitive), comma-separated hex-encoded patterns, hex-encoded
input, comma-separated chunk sizes for the streaming modes. See
README.md.

The output is a pure function of the seed and count. The fixed vectors
come first (the ones test/test_conformance.ml checks, so the reference
implementations confirm their expected values too), then random cases
drawn from small alphabets: with three or four symbols and short
patterns, patterns are dense with suffixes and overlaps of each other,
which is where Aho-Corasick implementations disagree if they are going
to. Every byte value, including NUL and bytes above 0x7f, appears in the
`bin` family; the `case` and `words` families exercise case folding.
"""

import argparse
import random
import sys

# (flags, patterns, input): the vectors in test/test_conformance.ml.
FIXED = [
    ("-", [], ""),
    ("-", ["a"], ""),
    ("-", ["a"], "a"),
    ("-", ["a"], "aa"),
    ("-", ["a"], "aaa"),
    ("-", ["a"], "aba"),
    ("-", ["a"], "bba"),
    ("-", ["a"], "bbb"),
    ("-", ["a"], "bababbbba"),
    ("-", ["aa"], ""),
    ("-", ["aa"], "aa"),
    ("-", ["aa"], "aabbaa"),
    ("-", ["aa"], "abbab"),
    ("-", ["aa"], "abbabaa"),
    ("-", ["abc"], "abc"),
    ("-", ["abc"], "zazabzabcz"),
    ("-", ["abc"], "zazabczabcz"),
    ("-", ["a", "b"], ""),
    ("-", ["a", "b"], "z"),
    ("-", ["a", "b"], "b"),
    ("-", ["a", "b"], "a"),
    ("-", ["a", "b"], "abba"),
    ("-", ["b", "a"], "abba"),
    ("-", ["abc", "bc"], "xbc"),
    ("-", ["foo", "bar"], ""),
    ("-", ["foo", "bar"], "foobar"),
    ("-", ["foo", "bar"], "barfoo"),
    ("-", ["foo", "bar"], "foofoo"),
    ("-", ["foo", "bar"], "barbar"),
    ("-", ["foo", "bar"], "bafofoo"),
    ("-", ["bar", "foo"], "bafofoo"),
    ("-", ["foo", "bar"], "fobabar"),
    ("-", ["bar", "foo"], "fobabar"),
    ("-", ["yabcdef", "abcdezghi"], "yabcdefghi"),
    ("-", ["yabcdef", "abcdezghi"], "yabcdezghi"),
    ("-", ["yabcdef", "bcdeyabc", "abcdezghi"], "yabcdezghi"),
    ("-", [], "a"),
    ("-", [], "abc"),
    ("-", ["ab", "abcd"], "abcd"),
    ("-", ["abcd", "ab"], "abcd"),
    ("-", ["abcd", "ab", "abc"], "abcd"),
    ("-", ["abcd", "abc", "ab"], "abcd"),
    ("-", ["abcd", "bcd", "cd", "b"], "abcd"),
    ("-", ["abcd", "bcd", "cd"], "abcd"),
    ("-", ["bcd", "cd", "abcd"], "abcd"),
    ("-", ["abc", "bc"], "zazabcz"),
    ("-", ["ab", "ba"], "abababa"),
    ("-", ["foo", "foo"], "foobarfoo"),
    ("-", ["abc", "abc"], "abcabc"),
    ("-", ["bcd", "cd", "b", "abcd"], "abcd"),
    ("-", ["bcd", "abcd", "cd"], "abcd"),
    ("-", ["foo", "foofoo"], "foofoo"),
    ("-", ["ab", "ab"], "abcd"),
    ("-", ["a", "ab"], "aa"),
    ("-", ["ab", "a"], "aa"),
    ("-", ["ab", "a"], "xayabbbz"),
    ("-", ["abcd", "bce", "b"], "abce"),
    ("-", ["abcd", "ce", "bc"], "abce"),
    ("-", ["abcd", "bce", "ce", "b"], "abce"),
    ("-", ["abcd", "bce", "cz", "bc"], "abcz"),
    ("-", ["bce", "cz", "bc"], "bcz"),
    ("-", ["abc", "bd", "ab"], "abd"),
    ("-", ["abcdefghi", "hz", "abcdefgh"], "abcdefghz"),
    ("-", ["abcdefghi", "cde", "hz", "abcdefgh"], "abcdefghz"),
    ("-", ["abcdefghi", "hz", "abcdefgh", "a"], "abcdefghz"),
    ("-", ["b", "abcdefghi", "hz", "abcdefgh"], "abcdefghz"),
    ("-", ["h", "abcdefghi", "hz", "abcdefgh"], "abcdefghz"),
    ("-", ["z", "abcdefghi", "hz", "abcdefgh"], "abcdefghz"),
    ("-", ["a", "a"], "abab"),
    ("-", ["a", "ab"], "a"),
    ("-", ["a", "ab"], "ab"),
    ("-", ["ab", "a"], "a"),
    ("-", ["ab", "a"], "ab"),
    ("-", ["abcdefg", "bcde", "bcdef"], "abcdef"),
    ("-", ["abcdefg", "bcdef", "bcde"], "abcdef"),
    ("-", ["abcd", "b", "bce"], "abce"),
    ("-", ["a", "abcdefghi", "hz", "abcdefgh"], "abcdefghz"),
    ("-", ["a", "abab"], "abab"),
    ("-", ["abcd", "b", "ce"], "abce"),
    ("-", ["a", "ab"], "xayabbbz"),
    ("i", ["a"], "A"),
    ("i", ["Samwise"], "SAMWISE"),
    ("i", ["Samwise"], "SAMWISE.abcd"),
    ("i", ["fOoBaR"], "quux foobar baz"),
    ("i", ["foo", "FOO"], "fOo"),
    ("i", ["FOO", "foo"], "fOo"),
    ("i", ["abc", "def"], "abcdef"),
    ("i", ["abc", "def", "abcdef"], "abcdef"),
    ("-", ["inf", "ind"], "infind"),
    ("-", ["ind", "inf"], "infind"),
    ("-", ["libcore/", "libstd/"], "libcore/char/methods.rs"),
    ("-", ["libstd/", "libcore/"], "libcore/char/methods.rs"),
    ("-", ["\x00\x00\x01", "\x00\x00\x00"], "\x00\x00\x00"),
    ("-", ["\x00\x00\x00", "\x00\x00\x01"], "\x00\x00\x00"),
    ("-", ["append", "appendage", "app"], "append the app to the appendage"),
    ("-", ["apple", "maple", "Snapple"], "Nobody likes maple in their apple flavored Snapple."),
    ("-", ["Samwise", "Sam"], "Samwise"),
    ("-", ["Sam", "Samwise"], "Samwise"),
    ("-", ["he", "her", "here"], "he here her"),
    ("-", ["b", "abc"], "abb"),
    ("-", ["b", "c", "abd"], "abc"),
    ("-", ["trimethoprim", "sulfamethoxazole", "meth"], "sulfamethoxazole and trimethoprim"),
    ("-", ["is", "this", "is this a dream?"], "is this a test?"),
    ("-", ["th", "this", "is this a dream?"], "is this a test?"),
    ("-", ["he", "she", "his", "hers"], "ushers"),
    ("-", ["a", "ab", "abc"], "abca"),
    ("-", ["aa"], "aaaa"),
    ("-", ["b", "ba"], "aba"),
    ("-", ["ab", "bc"], "abc"),
    ("-", ["x", "x"], "ax"),
    ("-", ["abc"], "xxabc-abc"),
    ("i", ["Rust"], "rust RUST rUsT"),
    ("-", ["é"], "café au lait"),
    ("-", ["ab/j/", "x/"], "ab/j/"),
    ("-", ["cat", "dog"], "cat and dog"),
    ("-", ["sam", "samwise"], "say samwise sam"),
]

ALPHABETS = {
    "ab": b"ab",
    "abc": b"abc",
    "abcd": b"abcd",
    "bin": bytes([0x00, 0x01, 0x7F, 0x80, 0xFF]),
    "case": b"aAbB",
}

WORDS = (
    "he she his hers her here hero the there them then than that this "
    "is it in an and any a ab abc abcd sam samwise sherlock holmes "
    "watson base baseball ball all al cat cats catalog dog dogma"
).split()


def rand_bytes(rng, alphabet, n):
    return bytes(rng.choice(alphabet) for _ in range(n))


def substring(rng, pattern):
    i = rng.randrange(len(pattern))
    j = rng.randrange(i + 1, len(pattern) + 1)
    return pattern[i:j]


def random_case(rng):
    family = rng.choice(["ab", "ab", "ab", "abc", "abc", "abc", "abcd", "bin", "case", "case", "words"])
    flags = "-"
    if family == "case":
        flags = "i" if rng.random() < 0.8 else "-"
    if family == "words":
        flags = "i" if rng.random() < 0.5 else "-"
        pool = [w.encode() for w in WORDS]
        patterns = []
        for _ in range(rng.choice([1, 2, 2, 3, 4, 6])):
            p = rng.choice(pool)
            if patterns and rng.random() < 0.15:
                p = rng.choice(patterns)
            elif rng.random() < 0.2:
                p = substring(rng, p)
            patterns.append(p)
        n = rng.randint(0, 25)
        words = [rng.choice(pool) if rng.random() < 0.7 else rng.choice(patterns) for _ in range(n)]
        if flags == "i":
            words = [w.upper() if rng.random() < 0.3 else w for w in words]
        text = b" ".join(words)
    else:
        alphabet = ALPHABETS[family]
        patterns = []
        for _ in range(rng.choice([1, 1, 2, 2, 3, 3, 4, 5, 6, 8])):
            r = rng.random()
            if patterns and r < 0.1:
                patterns.append(rng.choice(patterns))
            elif patterns and r < 0.3:
                patterns.append(substring(rng, rng.choice(patterns)))
            else:
                length = rng.choice([1, 1, 2, 2, 3, 3, 4, 5, 6]) if rng.random() < 0.9 else rng.randint(7, 12)
                patterns.append(rand_bytes(rng, alphabet, length))
        n = rng.choice([0, 1, 2, 5, 10, 20, 40, 64, 64, 100]) if rng.random() < 0.9 else rng.randint(100, 300)
        if rng.random() < 0.3:
            parts, total = [], 0
            while total < n:
                piece = rng.choice(patterns) if rng.random() < 0.6 else rand_bytes(rng, alphabet, rng.randint(0, 3))
                parts.append(piece)
                total += len(piece)
            text = b"".join(parts)[:n]
        else:
            text = rand_bytes(rng, alphabet, n)
    chunks = [rng.randint(0, 12) for _ in range(rng.randint(0, 5))]
    return flags, patterns, text, chunks


def emit(out, id_, flags, patterns, text, chunks):
    out.write(
        "\t".join(
            [
                str(id_),
                flags,
                ",".join(p.hex() for p in patterns),
                text.hex(),
                ",".join(str(c) for c in chunks),
            ]
        )
        + "\n"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--seed", type=int, default=20260904)
    parser.add_argument("--count", type=int, default=20000, help="number of random cases after the fixed ones")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    out = sys.stdout
    out.write(f"# seed={args.seed} count={args.count} fixed={len(FIXED)}\n")
    id_ = 0
    for flags, patterns, text in FIXED:
        for chunks in ([], [1] * len(text), [3, 0, 2]):
            emit(out, id_, flags, [p.encode("utf-8") for p in patterns], text.encode("utf-8"), chunks)
            id_ += 1
    for _ in range(args.count):
        emit(out, id_, *random_case(rng))
        id_ += 1


if __name__ == "__main__":
    main()
