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

Stage 2 (2026-11-06): `geo_vctr` over Arrow memory, registered with
zuarrow for every GeoArrow name, with subsetting,
[`c()`](https://rdrr.io/r/base/c.html),
[`is.na()`](https://rdrr.io/r/base/NA.html),
[`format()`](https://rdrr.io/r/base/format.html) as WKT and export.
Stage 1 gave
[`geo_type_of()`](https://pedrobtz.github.io/zugeo/reference/geo_type_of.md),
[`geo_crs()`](https://pedrobtz.github.io/zugeo/reference/geo_crs.md) and
[`geo_crs_equal()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_equal.md);
Stage 0 the package, CI and vendored `geoarrow-c`. No encoding
conversions yet (Stage 3). The roadmap in `.agents/roadmap.md` takes it
to v0.1.0.

## Versions and dependents

The current version’s parent issue is the `v0.1.0` issue, created by
`pkg-roadmap`. Sibling packages that depend on this one before CRAN
does: none yet. `qio` (GeoParquet), `zuclip` and `zucdt` are expected
consumers (design §3).

## Commands

- `tools/verify-vendor`: re-derives `src/vendor/` from the pinned commit
  and fails on any difference. CI runs it (`vendor.yaml`). Needs
  `cmake`, `curl`, `shasum` and `python3`.
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

- `src/zgo_schema.c`: the schema view, zugeo’s own (design D20), behind
  [`geo_type_of()`](https://pedrobtz.github.io/zugeo/reference/geo_type_of.md).
  It reads the `ArrowSchema` behind any nanoarrow-layout handle
  (zuarrow’s or nanoarrow’s).
- `src/zgo_build.c`: builds schemas from an R spec (`zgo_schema()`,
  `zgo_spec()` in `R/build.R`), for tests now and export in Stage 2.
- `R/type.R` turns the C description into a `zugeo_type` and parses the
  extension metadata with zujson; `R/crs.R` is `zugeo_crs`,
  classification and the three equality levels.
- `src/zgo_array.c`: [`is.na()`](https://rdrr.io/r/base/NA.html),
  [`format()`](https://rdrr.io/r/base/format.html) and gathering over a
  `geo_vctr`’s chunks; the native walk into `geoarrow-c`’s
  `GeoArrowVisitor` (design D21).
- `R/vctr.R`: the `geo_vctr` class (positions plus `chunks`, `starts`,
  `schema` attributes) and its methods; `R/zzz.R` registers the eleven
  names and the class with zuarrow in `.onLoad()`.

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
- **C never raises a zugeo condition.** It returns a `zgo_failure` list
  (`kind`, `message`) and R’s `zgo_check()` raises it, as
  `zugeo_<kind>_error`. Plain `Rf_error()` is only for misuse of an
  internal routine. C that holds heap memory must not call R in between
  (`zgo_build.c` lets the external pointer own the schema first).
  `zgo_array.c` registers every view, writer and built array with a
  scratch external pointer as soon as it exists; keep that pattern for
  new C.
- **Unions are built with type ids `0..n-1` and remapped** (design D21):
  nanoarrow builds no other. A new builder over unions must do the same.
- **`geoarrow-c`’s WKB visit emits its own `feat_start()` and
  `feat_end()`**, and a visitor returning `EAGAIN` (the WKT writer’s
  size limit) leaves the caller to call `feat_end()`.

## Testing

The conformance corpus is `geoarrow-data` `v0.2.0` (design §9), with
`geoarrow`, `arrow`/pyarrow, DuckDB spatial, `sf`, `geos`, `s2`, `wk`,
`gpq`, and flatbush/kdbush under `node` as oracles. The corpus has no
union-encoded `geoarrow.geometry` file; Stage 2 makes one. Helpers:
`helper-abi.R` reads the shared object’s export and import tables (`nm`,
or `objdump` on Windows; a failure on CI, a skip elsewhere);
`helper-ci-oracles.R` has `skip_without_oracle()`, which fails under
`ZUGEO_ORACLES=true`; `helper-schema.R` builds GeoArrow schemas from
specs (`ga_schema()`, `ga_union()`, `ga_field()`); `helper-corpus.R`
fetches the corpus; `helper-vctr.R` reads the union fixture
(`tests/testthat/data/geometry-union.arrows`, zuarrow’s, from
`tools/make-union-fixture.py`) and round-trips data frames. The corpus
is never in the package (no licence): it is fetched from `geoarrow-data`
at commit `e8eaa04` when `ZUGEO_FETCH_FIXTURES=true` (set in every CI
workflow), or read from `ZUGEO_CORPUS_DIR`, and checked against
`tests/testthat/corpus.txt`; otherwise the corpus tests skip.

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
fast_float or ryu, and the nanoarrow 0.9.0 release core (not the 0.8.0
`geoarrow-c` pins, which GCC 16 warns on), bundled by nanoarrow’s own
`bundle.py` and namespaced as `ZugeoNanoarrow`. No local patches.
`src/vendor/PROVENANCE` has the pins and checksums; `inst/COPYRIGHTS`
the notices.
