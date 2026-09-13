# Development

[Back to README](../README.md) · [Release procedure](releasing.md)

## Build and test

Use OCaml >= 4.14 and Dune >= 3.17.2 in an opam switch:

```sh
opam install . --deps-only --with-test --with-doc
opam exec -- dune build @all @doc
opam exec -- dune runtest
opam lint aho-corasick.opam
```

Use `opam exec --` to avoid mixing the switch's libraries with a system
compiler. The generated API entry point is
`_build/default/_doc/_html/aho-corasick/Aho_corasick/index.html`.

`dune-project` owns package metadata. After editing it, regenerate and check
the tracked opam file:

```sh
opam exec -- dune build aho-corasick.opam
git diff -- aho-corasick.opam
```

## Tests

Alcotest covers overlaps, duplicate IDs, empty inputs, accessors, ASCII
folding, binary data, chunk boundaries, flush behavior, and state reuse.
A large dense chunk exercises streamed selection without a timing threshold.

QCheck compares search results with an independent per-pattern scan,
including exact ordering, and checks leftmost-longest selection against a
reference that tries every pattern at each input position. Streaming modes
are checked across random chunk splits, including empty chunks, empty
pattern sets, mixed case, and arbitrary bytes. Replacement is checked
against independently selected matches.

`test/test_conformance.ml` ports vectors from Rust `aho-corasick`,
daachorse, and pyahocorasick. The separate `compat/` harness compares this
library with Rust `aho-corasick`, pyahocorasick, and ahocorasick_rs over
20,000 generated cases. `bench/` runs reproducible, count-checked throughput
measurements; see the READMEs in those directories for prerequisites.

To replay a QCheck failure using the seed printed by the test runner:

```sh
QCHECK_SEED=12345 opam exec -- dune runtest --force
```

CI covers OCaml 4.14 and 5.4, documentation generation, opam lint, generated
metadata consistency, package installation, and website links. A separate
lower-bounds job uses OCaml 4.14.0 and the declared minimum Dune, Alcotest,
and QCheck versions. Another job runs the differential harness and a
benchmark smoke test.

## Website

The website is static HTML and CSS under `website/`. Keep its introductions
short; full signatures belong in `src/aho_corasick.mli` and recipes in
`docs/usage.md`. Existing page URLs remain stable.

Assemble the same site that Pages publishes:

```sh
opam exec -- dune build @doc
mkdir -p _site/api
cp -R website/. _site/
cp -R _build/default/_doc/_html/. _site/api/
python3 scripts/check_site.py _site
python3 -m http.server 8000 --directory _site
```

Open `http://localhost:8000/`. GitHub Pages deploys from `main` when website,
library, package, or Pages workflow files change.

## Reporting a bug

Include the compiler version, pattern list, input bytes, expected and actual
matches, and the exact chunks if streaming is involved. Add a small
regression test with the fix.
