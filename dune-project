(lang dune 3.14)
(name aho-corasick)
(version 0.1.1)

(generate_opam_files true)

(source (github thevilledev/ocaml-aho-corasick))
(license MIT)
(authors "Ville Vesilehto <ville@vesilehto.fi>")
(maintainers "Ville Vesilehto <ville@vesilehto.fi>")
(homepage "https://ville.dev/ocaml-aho-corasick/")

(package
 (name aho-corasick)
 (synopsis "Aho-Corasick multi-pattern string matching")
 (description
  "Multi-pattern matching over byte strings in pure OCaml, with no runtime dependencies beyond the standard library. Supports overlapping search, lazy iteration, leftmost-longest selection, replacement, ASCII case folding, and chunked streaming in three match modes. Automata are immutable and reusable. Search is linear in the input plus matches examined; leftmost-longest selection uses lookahead bounded by the longest pattern.")
 (depends
  (ocaml (>= 4.14))
  (alcotest (and :with-test (>= 1.5.0)))
  (qcheck-core (and :with-test (>= 0.25)))
  (qcheck-alcotest (and :with-test (>= 0.25))))
 (tags ("string" "search" "aho-corasick")))
