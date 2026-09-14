# Releasing

[Back to README](../README.md) · [Changelog](../CHANGES.md)

The v0.1.1 files are prepared locally. Publication requires a pushed commit
and tag, a public source archive, and an opam-repository submission. Local
preparation alone does not make `opam install aho-corasick` available.

## Validate locally

1. Set the version in `dune-project` and finalize the matching entry in
   `CHANGES.md`. Regenerate `aho-corasick.opam` with Dune.
2. Run the [development checks](development.md#build-and-test) and confirm
   that CI passes on both supported compiler versions.
3. Test the package build and install in a disposable switch or prefix:

   ```sh
   opam exec -- dune build -p aho-corasick @install @runtest @doc
   opam exec -- dune install --prefix /tmp/aho-corasick-install aho-corasick
   ```

4. Check that the installed library, README, changelog, license, and guides
   are present. Commit the release changes and leave the worktree clean.

## Tag and archive

These steps are for the maintainer when publication is approved. Use the
same release commit that passed validation.

```sh
git tag -s v0.1.1 -m 'Release v0.1.1'
mkdir -p _release
git archive --format=tar --prefix=aho-corasick-0.1.1/ v0.1.1 \
  | gzip -n > _release/aho-corasick-0.1.1.tar.gz
```

Unpack the archive in a fresh directory and repeat the package build there.
A local rehearsal can use `HEAD` instead of the tag. The archive should
contain tracked source only, with no `_build`, `_opam`, or `_site` files.

Push the release commit and tag, create the GitHub release using the
changelog, and upload this archive as an asset. Prefer an uploaded archive
over a forge-generated archive whose checksum might later change. Never
replace an archive once opam-repository references it.

Expected asset URL:
`https://github.com/thevilledev/ocaml-aho-corasick/releases/download/v0.1.1/aho-corasick-0.1.1.tar.gz`.
Verify the public download against the local archive before submitting.

## Submit to opam-repository

The source-tree `aho-corasick.opam` deliberately has no release `url`
section: the archive does not exist publicly during local preparation.
`dune-project` remains the source of truth for upstream metadata.

After uploading the release asset, use `opam-publish` to add its URL and
checksums and prepare the repository submission:

```sh
opam install opam-publish
opam publish -v 0.1.1 \
  https://github.com/thevilledev/ocaml-aho-corasick/releases/download/v0.1.1/aho-corasick-0.1.1.tar.gz .
```

Review the generated `packages/aho-corasick/aho-corasick.0.1.1/opam`.
The repository copy should omit source-tree `name` and `version` fields
and contain the immutable archive URL plus SHA-256 or stronger checksums.
Keep OCaml/Dune constraints and test/doc dependency filters consistent with
the upstream file. Fix any opam-repository CI failures before merging.

After the package is merged, verify installation from a fresh switch and
remove the pre-publication install note from the README and website. Check
the deployed guides and generated API links as part of publication.

References: [opam packaging guide](https://opam.ocaml.org/doc/Packaging.html),
[opam-repository contribution guide](https://github.com/ocaml/opam-repository/blob/master/CONTRIBUTING.md).
