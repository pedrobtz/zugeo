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
invented. `Imports` are `zuarrow` and `zujson` only. No package outside
the family appears in `DESCRIPTION`: `sf`, `wk`, `geos`, `s2`,
`geoarrow`, `nanoarrow`, `arrow` and `duckdb` are CI-only oracles. No
system library. It is not a geometry engine, not a projection library
and not an `sf` replacement; WKB and a CRS string are the bridge to
those.

The specification is
[`.agents/design.md`](https://pedrobtz.github.io/zugeo/.agents/design.md),
adopted from RFC 0071. It outranks this file.

## Current state

Scaffolded 2026-11-05 with `create-pkg.sh` (C, through `use_c()`); no
functionality yet. The roadmap in `.agents/roadmap.md` takes it to
v0.1.0.

## Versions and dependents

The current version’s parent issue is the `v0.1.0` issue, created by
`pkg-roadmap`. Sibling packages that depend on this one before CRAN
does: none yet. `qio` (GeoParquet), `zuclip` and `zucdt` are expected
consumers (design §3).

## Commands

None beyond the shared ones yet.

## Architecture

To be written as stages land; see `.agents/design.md` §4. The scaffold
has the C layer from `use_c()`: `src/zugeo.c` and
`@useDynLib zugeo, .registration = TRUE` in `R/zugeo-package.R`.

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

## Testing

The conformance corpus is `geoarrow-data` `v0.2.0` (design §9), with
`geoarrow`, `arrow`/pyarrow, DuckDB spatial, `sf`, `geos`, `s2`, `wk`,
`gpq`, and flatbush/kdbush under `node` as oracles. None is wired up
yet. No helpers yet.

## Continuous integration

Calls the shared `r-cmd-check.yml` and `coverage.yml` from
`pedrobtz/r-actions@v1`, and its own `pkgdown.yaml`. The design plans an
`oracles` workflow (Stage 3) that runs the CI-only tests with
`ZUGEO_ORACLES=true`. Stages 2, 6 and 9 are `full`.

## Vendored native code

`geoarrow-c` and the nanoarrow core it builds on, both Apache-2.0,
pinned in Stage 0 (design §7). Not vendored yet; fill in the version and
local patches when it is.
