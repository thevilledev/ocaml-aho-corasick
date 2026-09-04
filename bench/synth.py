#!/usr/bin/env python3
"""Generate the synthetic benchmark corpora, deterministically.

  synth.py <output-dir>

- abc-{64k,256k,1m,4m}.txt: uniformly random text over the alphabet abc,
  each a prefix of the next, with abc-patterns.txt holding every string
  of length 1 to 3 over that alphabet (39 patterns). About three matches
  end at every byte, which makes match reporting, not scanning, the cost.
  The four sizes are the scaling series.
- bytes-1m.bin with bytes-patterns.txt: uniformly random bytes and 100
  random 8-byte printable patterns, so almost nothing matches and the
  cost is the automaton alone, over every byte value.
- aaaa-200k.txt with a-suffixes.txt: 200 000 a's against a, aa, ..., a^20,
  the pathological overlapping case, with about 20 matches per byte.
"""

import itertools
import os
import random
import sys


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)

    def write(name, data):
        path = os.path.join(out, name)
        if not os.path.exists(path):
            with open(path, "wb") as f:
                f.write(data)

    rng = random.Random(1)
    abc = bytes(rng.choice(b"abc") for _ in range(4 << 20))
    for size, name in [(64 << 10, "abc-64k.txt"), (256 << 10, "abc-256k.txt"), (1 << 20, "abc-1m.txt"), (4 << 20, "abc-4m.txt")]:
        write(name, abc[:size])
    write("abc-patterns.txt", b"\n".join(bytes(p) for n in (1, 2, 3) for p in itertools.product(b"abc", repeat=n)) + b"\n")

    rng = random.Random(2)
    write("bytes-1m.bin", bytes(rng.randrange(256) for _ in range(1 << 20)))
    printable = bytes(range(0x21, 0x7F))
    write("bytes-patterns.txt", b"\n".join(bytes(rng.choice(printable) for _ in range(8)) for _ in range(100)) + b"\n")

    write("aaaa-200k.txt", b"a" * 200_000)
    write("a-suffixes.txt", b"\n".join(b"a" * n for n in range(1, 21)) + b"\n")


if __name__ == "__main__":
    main()
