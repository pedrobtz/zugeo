# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Shared conventions

The portfolio’s shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this
file and a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md @.claude/shared/r-package.md
@.claude/shared/ci.md @.claude/shared/native-code.md

## What this is

zugeo makes GeoArrow a first-class column type in R. It registers every
`geoarrow.*` extension name with `zuarrow`, keeps geometries in Arrow
memory as a `geo_vctr`, computes bounds, Hilbert keys and spatial sorts
over the coordinate buffers, builds flatbush- and kdbush-format packed
indexes, and, with `qio` 0.2.0, reads and writes GeoParquet. Every
conversion is exact or an error; a CRS is carried, never resolved or
invented. `Imports` are `zuarrow` and `zujson` only, and `LinkingTo` is
`zufast` (from Stage 3, design D18). No package outside the family
appears in `DESCRIPTION`: `sf`, `wk`, `geos`, `s2`, `geoarrow`,
`nanoarrow`, `arrow` and `duckdb` are CI-only oracles. No system
library. It is not a geometry engine, not a projection library and not
an `sf` replacement; WKB and a CRS string are the bridge to those.

The specification is
[`.agents/design.md`](https://pedrobtz.github.io/zugeo/.agents/design.md),
adopted from RFC 0071. It outranks this file.

## Current state

Stage 0 (2026-11-06): package identity, CI, and `geoarrow-c` with its
nanoarrow core vendored, namespaced and hidden;
[`zugeo_info()`](https://pedrobtz.github.io/zugeo/reference/zugeo_info.md)
is the only function. No geometry functionality yet. The roadmap in
`.agents/roadmap.md` takes it to v0.1.0.

## Versions and dependents

The current version’s parent issue is the `v0.1.0` issue, created by
`pkg-roadmap`. Sibling packages that depend on this one before CRAN
does: none yet. `qio` (GeoParquet), `zuclip` and `zucdt` are expected
consumers (design §3).

## Commands

- `tools/verify-vendor`: re-derives `src/vendor/` from the pinned commit
  and fails on any difference. CI runs it (`vendor.yaml`). Needs
  `cmake`, `curl` and `shasum`.
- `tools/update-vendor`: after changing a pin in `tools/derive-vendor`,
  re-derives the tree and rewrites `src/vendor/PROVENANCE`; then update
  the commit in `src/zgo.h` and the versions in `test-info.R`,
  `inst/COPYRIGHTS` and `DESCRIPTION`.
- `ZUGEO_ORACLES=true Rscript -e 'devtools::test(filter = "^ci-")'`: the
  CI-only oracle tests, with a missing oracle as a failure.

## Architecture

To be written as stages land; see `.agents/design.md` §4. So far:
`src/zugeo.c` registers the `.Call` routines (`R_forceSymbols`, so R
calls them by symbol object, `.Call(zgo_c_info)`); `src/zgo.h` is the
internal header; `src/vendor/` is the vendored C, built by the objects
listed in `src/Makevars` (and its copy `Makevars.win`).

## Invariants that are easy to break

- **Nothing outside the family in `DESCRIPTION`**, not even `Suggests`
  (design D3). Oracle tests live in `tests/testthat/test-ci-*.R`, which
  `.Rbuildignore` keeps out of the tarball.
- **No JSON code in `src/`** (D4). Extension metadata, the GeoParquet
  `geo` key and PROJJSON go through `zujson`.
- **The vendored nanoarrow core is namespaced** as `ZugeoNanoarrow`
  (D2), and every symbol is hidden. An unnamespaced copy clashes with
  `zuarrow`’s copy or a loaded `nanoarrow`.
- **A CRS is never resolved, guessed or dropped** (D6). Checks inside
  zugeo use `geo_crs_equal(level = "identical")` only (D14).
- **Subsetting and sorting a `geo_vctr` never copy buffers** (D5).
- **Index bytes stay flatbush- and kdbush-compatible** (D13).
- **Never edit `src/vendor/` by hand.** It is `tools/derive-vendor`’s
  output, byte for byte; `vendor.yaml` fails otherwise. A change to
  vendored code is a patch the derivation applies, recorded in
  `src/vendor/PROVENANCE`.
- **`R_init_zugeo` is the only exported symbol, and no `assert`, `abort`
  or `printf` is imported.** Keep `$(C_VISIBILITY)`, `-DNANOARROW_DLL=`
  and `src/zugeo-win.def`. Don’t rely on `-DNDEBUG`: the gctorture build
  ignores it, which is why ryu is not vendored. `test-abi.R` checks both
  tables.
- **`src/Makevars` and `src/Makevars.win` stay identical.**

## Testing

The conformance corpus is `geoarrow-data` `v0.2.0` (design §9), with
`geoarrow`, `arrow`/pyarrow, DuckDB spatial, `sf`, `geos`, `s2`, `wk`,
`gpq`, and flatbush/kdbush under `node` as oracles. The corpus has no
union-encoded `geoarrow.geometry` file; Stage 2 makes one. Helpers:
`helper-abi.R` reads the shared object’s export and import tables (`nm`,
or `objdump` on Windows; a failure on CI, a skip elsewhere);
`helper-ci-oracles.R` has `skip_without_oracle()`, which fails under
`ZUGEO_ORACLES=true`.

## Continuous integration

Calls from `pedrobtz/r-actions@v1`: `r-cmd-check.yml` (with Windows
R-devel added to `runners`), `coverage.yml`, the native checks in
`native-checks.yaml` (sanitizers with ASan, valgrind, LTO, rchk,
analyzers, cran-special), `gctorture.yml` (quick step on pushes, step 20
on a daily schedule), `vendor.yml`, and `vendor-upstream.yml` weekly.
Its own workflows: `pkgdown.yaml`, and `oracles.yaml`, which runs the
`test-ci-*.R` files with `ZUGEO_ORACLES=true` because r-actions has no
workflow for tests outside the tarball. Stages 2, 3 and 6 are `full`,
with the closing three.

## Vendored native code

`geoarrow-c` at commit `b3db89f` (0.2.0-SNAPSHOT, Apache-2.0), bundled
by upstream’s CMake bundler with `GEOARROW_NAMESPACE=Zugeo` and without
fast_float or ryu, and the nanoarrow 0.8.0 core `geoarrow-c` vendors,
namespaced as `ZugeoNanoarrow` in `src/Makevars`. No local patches.
`src/vendor/PROVENANCE` has the pins and checksums; `inst/COPYRIGHTS`
the notices.
