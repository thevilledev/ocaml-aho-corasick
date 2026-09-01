(lang dune 3.17)
(name aho-corasick)
(version 0.1.0)

(generate_opam_files true)

(source (github thevilledev/ocaml-aho-corasick))
(license MIT)
(authors "Ville Vesilehto <ville@vesilehto.fi>")
(maintainers "Ville Vesilehto <ville@vesilehto.fi>")
(documentation "https://ville.dev/ocaml-aho-corasick/api/")

(package
 (name aho-corasick)
 (synopsis "Aho-Corasick multi-pattern string matching")
 (description
  "Simultaneous search for many patterns in one pass over the input. Builds the classic Aho-Corasick automaton (trie + failure links + dictionary suffix links) from a list of byte-string patterns, then finds all overlapping matches, leftmost-longest non-overlapping matches, or streaming matches across chunk boundaries, in time linear in input size and independent of pattern count. The workhorse behind secret scanners, WAF signature matching, log filtering and dictionary tagging. Pure OCaml, zero dependencies.")
 (depends
  (ocaml (>= 4.14))
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test))
 (tags (aho-corasick "string matching" "multi-pattern" scanning "org:thevilledev")))
