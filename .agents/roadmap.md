# zugeo: roadmap

Status: draft 2026-11-05. Implements [design.md](design.md); the stages
are the design's former §11, which moved here on adoption, keeping its
numbering so the design's stage references still hold.
Target: v0.1.0, the first CRAN release.
Tracking: [v0.1.0 (#1)](https://github.com/pedrobtz/zugeo/issues/1),
with one sub-issue per stage;
[CRAN-submission (#14)](https://github.com/pedrobtz/zugeo/issues/14).

## Stages

<!-- markdownlint-disable MD013 -->
| Stage | Title | CI | Issue | Pull request | Done |
| --- | --- | --- | --- | --- | --- |
| 0 | [Package identity and vendored C](#stage-0--package-identity-and-vendored-c) | quick | [#2](https://github.com/pedrobtz/zugeo/issues/2) | | 2026-11-06 |
| 1 | [Schemas, metadata and CRS](#stage-1--schemas-metadata-and-crs) | quick | [#3](https://github.com/pedrobtz/zugeo/issues/3) | | |
| 2 | [geo_vctr and the zuarrow registry](#stage-2--geo_vctr-and-the-zuarrow-registry) | full | [#4](https://github.com/pedrobtz/zugeo/issues/4) | | |
| 3 | [Encodings and interchange](#stage-3--encodings-and-interchange) | full | [#5](https://github.com/pedrobtz/zugeo/issues/5) | | |
| 4 | [Exactness errors](#stage-4--exactness-errors) | quick | [#6](https://github.com/pedrobtz/zugeo/issues/6) | | |
| 5 | [Visitor, extents and kernels](#stage-5--visitor-extents-and-kernels) | quick | [#7](https://github.com/pedrobtz/zugeo/issues/7) | | |
| 6 | [Packed indexes](#stage-6--packed-indexes) | full | [#8](https://github.com/pedrobtz/zugeo/issues/8) | | |
| 7 | [GeoParquet](#stage-7--geoparquet) | quick | [#9](https://github.com/pedrobtz/zugeo/issues/9) | | |
| 8 | [Documentation and benchmarks](#stage-8--documentation-and-benchmarks) | quick | [#10](https://github.com/pedrobtz/zugeo/issues/10) | | |
| 9 | [Full CI](#stage-9--full-ci) | full | [#11](https://github.com/pedrobtz/zugeo/issues/11) | | |
| 10 | [v0.1.0 readiness](#stage-10--v010-readiness) | full | [#12](https://github.com/pedrobtz/zugeo/issues/12) | | |
| 11 | [Review](#stage-11--review) | full | [#13](https://github.com/pedrobtz/zugeo/issues/13) | | |
<!-- markdownlint-enable MD013 -->

## Stage 0 — Package identity and vendored C

**Issue.** [#2](https://github.com/pedrobtz/zugeo/issues/2), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `quick`. The vendored library is compiled and loaded here, but
nothing calls into it until Stages 1 to 3; the full set checks it there,
when tests exercise it.

**Goal.** A real package identity, CI tuned for quick pull requests, and
`geoarrow-c` with its own namespaced nanoarrow core building and loading
beside the family's and outside packages' copies.

**Work.**

- `DESCRIPTION`: Title, Description, `Authors@R` (`aut`, `cre`, `cph`,
  plus the `geoarrow-c` and nanoarrow copyright holders), `Depends: R
  (>= 4.1)`, `Imports: zuarrow, zujson`, `Suggests: testthat (>= 3.0.0),
  withr`, `Language: en-GB`.
- `{"os": "windows-latest", "r": "devel"}` in the `R-CMD-check` caller's
  `runners`.
- `geoarrow-c` at `b3db89f` and its nanoarrow core under `src/vendor/`,
  `NANOARROW_NAMESPACE=ZugeoNanoarrow`, hidden symbols,
  `inst/COPYRIGHTS`, a vendoring script.
- `nm` checks: no `zgo_` or `GeoArrow`/`ArrowArray` clash with installed
  `zu*` packages, `geoarrow`, `nanoarrow` or `arrow`; no `printf`,
  `abort` or `exit` in the shared object. The `geo_` prefix checked
  against CRAN (D7).
- `zugeo_info()`; `zugeo_error` root condition.

*Deviation, 2026-11-06:* `Imports` are added by the stage that first
calls each package, because an unused import is an `R CMD check` NOTE:
`zujson` in Stage 1, `zuarrow` with `Remotes: pedrobtz/zuarrow` in
Stage 2. The `oracles` workflow arrives here rather than in Stage 3,
with only `zuarrow`, `geoarrow` and `nanoarrow`, because this stage's
coexistence criterion needs it; Stage 3 adds the other oracles.

**Exit criteria.**

- `R CMD check` passes on the quick r-actions profile, every check in
  under five minutes (tuning recorded here if needed).
- A test loads zugeo, `zuarrow`, `geoarrow` and `nanoarrow` in one
  session and calls each; the `nm` checks pass in CI.
- `zugeo_info()` reports the vendored versions and GeoArrow 0.2.

**Design.** [§3](design.md#3-position-in-the-zu-family),
[§7](design.md#7-vendored-code), D2, D3, D7.

## Stage 1 — Schemas, metadata and CRS

**Issue.** [#3](https://github.com/pedrobtz/zugeo/issues/3), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `quick`.

**Goal.** zugeo understands every GeoArrow schema and its metadata.

**Work.**

- Schema views for the eleven extension names, every layout, dimension,
  offset width and view storage type; `geo_type_of()`.
- `crs` and `edges` metadata parsed and written through `zujson`;
  `zugeo_crs`; `geo_crs_equal()` at its three levels.
- `zugeo_metadata_error`; the `geoarrow-data` corpus pinned by hash.

**Exit criteria.**

- Every `geoarrow-data` schema is described correctly by
  `geo_type_of()`.
- A table of CRS pairs gives each level's expected `TRUE`, `FALSE` or
  `NA`.

**Design.** [§2](design.md#2-scope),
[§6.2](design.md#62-types-and-layouts), [§6.4](design.md#64-crs), D4,
D6, D14.

## Stage 2 — geo_vctr and the zuarrow registry

**Issue.** [#4](https://github.com/pedrobtz/zugeo/issues/4), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `full — the registry, zugeo's vendored nanoarrow and zuarrow's
own copy meet here first, with array handles held as external pointers:
gctorture, valgrind, ASan.`

**Goal.** Geometry columns read through `zuarrow` arrive as `geo_vctr`
and leave unchanged.

**Work.**

- `geo_vctr` over chunks and a schema; `[`, `length()`, `c()`,
  `format()`, `is.na()`, `as.data.frame()`, `rev()`.
- `to` and `from` registrations for the eleven names and `geo_vctr` in
  `.onLoad()`.
- `zugeo_crs_error` for `c()` across CRS or edges.

**Exit criteria.**

- Every corpus file round-trips through `arrow_read()` and
  `arrow_write()` byte for byte in its extension metadata and value for
  value in its coordinates.
- A full-profile run is green on the pull request.

**Design.** [§6.1](design.md#61-geo_vctr),
[§6.5](design.md#65-registration-with-zuarrow), D5, D8.

## Stage 3 — Encodings and interchange

**Issue.** [#5](https://github.com/pedrobtz/zugeo/issues/5), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `full — first parsers of untrusted input (WKB, EWKB, hex WKB,
WKT): ASan, valgrind.`

**Goal.** Geometries move between encodings, and to and from other R
spatial packages by WKB and coordinates, exactly.

**Work.**

- `geo_as_wkb()`, `geo_as_wkt()`, `geo_as_native()`; `geo_vctr()` from
  WKB, EWKB, hex WKB and WKT; `geo_crs_text()`.
- `geo_coords()`, `geo_from_coords()`, `geo_points()`.
- The `oracles` workflow and `tests/testthat/test-ci-*.R`, run with
  `ZUGEO_ORACLES=true`.
- Truncated and malformed WKB and WKT tests.

**Exit criteria.**

- The round-trip property test of §6.3 passes on every corpus
  coordinate.
- The `sf`, `geos` and `s2` oracles read and write the corpus by WKB,
  and `sf` keeps the CRS from `geo_crs_text()`.
- A full-profile run is green on the pull request.

**Design.** [§6.3](design.md#63-exact-or-error),
[§6.6](design.md#66-interchange-with-other-packages),
[§6.10](design.md#610-coordinates-as-columns),
[§9](design.md#9-testing).

## Stage 4 — Exactness errors

**Issue.** [#6](https://github.com/pedrobtz/zugeo/issues/6), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `quick`.

**Goal.** Every lossy case of §6.3 errors, warns or passes as the
caller's `lossy` asks.

**Work.**

- `zugeo_edges_error`, `zugeo_layout_error`; `lossy` threaded from
  `arrow_to_r()` through the handlers.
- The edge-type and CRS matrix of tests.

**Exit criteria.**

- The edge and CRS matrix passes; every §6.3 error has a test that
  raises it.

**Design.** [§6.3](design.md#63-exact-or-error),
[§8](design.md#8-errors).

## Stage 5 — Visitor, extents and kernels

**Issue.** [#7](https://github.com/pedrobtz/zugeo/issues/7), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `quick`.

**Goal.** Bounds, counts, types, Hilbert keys, sorting and validation
over the buffers, all through one visitor.

**Work.**

- The coordinate visitor (D15) over native layouts and through
  `geoarrow-c` for WKB and WKT.
- `geo_extent` and its set operations.
- `geo_box()`, `geo_box_all()`, `geo_types()`, `geo_dims()`,
  `geo_n_coords()`, `geo_hilbert()`, `geo_sort()`, `geo_validate()`.

**Exit criteria.**

- Results equal the `sf` and flatbush oracles and `geoarrow-c`'s `box`
  kernels on the corpus.
- Q9 is answered against DuckDB and the answer recorded in the design.

**Design.** [§4](design.md#4-architecture),
[§6.7](design.md#67-bounds-hilbert-keys-and-sorting),
[§6.11](design.md#611-validation), D15, D16.

## Stage 6 — Packed indexes

**Issue.** [#8](https://github.com/pedrobtz/zugeo/issues/8), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `full — persisted index bytes are untrusted input: hostile
headers under ASan and valgrind.`

**Goal.** Persisted R-tree and k-d tree indexes that other languages
read unchanged.

**Work.**

- `geo_rtree()`, `geo_kdtree()`, `geo_query_box()`,
  `geo_query_radius()`, `geo_nearest()`.
- `geo_join_box()` against a vector and against a second index.
- `geo_index_raw()`, `geo_index_from_raw()`, `zugeo_index_error`.
- `node` (flatbush, kdbush) and Python (`geo-index`) CI legs.

**Exit criteria.**

- The `node` and `geo-index` legs return the same results over the same
  bytes.
- Both joins equal a brute-force scan on random data.
- A full-profile run is green on the pull request.

**Design.** [§6.8](design.md#68-packed-indexes), D13.

## Stage 7 — GeoParquet

**Issue.** [#9](https://github.com/pedrobtz/zugeo/issues/9), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `quick`.

**Goal.** GeoParquet 1.1 and 2.0 read and written over `qio` 0.2.0, or
the recorded decision to move this to zugeo 0.2.0 (D12).

**Work.**

- `geo_read_parquet()`, `geo_write_parquet()`, `geo_parquet_info()`,
  `geo_validate_parquet()`, `zugeo_parquet_error`.
- `qio` added to `Suggests` with guards.

**Exit criteria.**

- DuckDB and GDAL read every file zugeo writes, and `gpq validate`
  agrees with `geo_validate_parquet()` on the corpus.
- Or: D12 invoked, the reason in `NEWS.md`, and this stage moved to
  "After 0.1.0".

**Design.** [§6.9](design.md#69-geoparquet),
[§6.11](design.md#611-validation), D10, D12, D17.

## Stage 8 — Documentation and benchmarks

**Issue.** [#10](https://github.com/pedrobtz/zugeo/issues/10), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `quick`.

**Goal.** A user can learn zugeo from its README and article, and §10's
targets are measured.

**Work.**

- README, reference pages, the article "Geometry columns from DuckDB to
  sf".
- The CI-only benchmark script against `sf` and `geoarrow`.

**Exit criteria.**

- Every example runs; the pkgdown site builds.
- §10's measurements recorded in the design, missed targets included.

**Design.** [§10](design.md#10-performance-targets).

## Stage 9 — Full CI

**Issue.** [#11](https://github.com/pedrobtz/zugeo/issues/11), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `full`, always.

**Goal.** The default branch passes the whole r-actions profile.

**Work.**

- No new features. Run the full profile (`full-ci` label) and fix what
  it finds: gctorture, valgrind, ASan, every platform leg, `nosuggests`,
  `nold`, cran-special.

**Exit criteria.**

- A full-profile run is green on the pull request and on the merge
  commit.

**Design.** [§12](design.md#12-acceptance-criteria-for-v010).

## Stage 10 — v0.1.0 readiness

**Issue.** [#12](https://github.com/pedrobtz/zugeo/issues/12), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1).

**CI.** `full`, always.

**Goal.** The package is versioned and documented for submission.

**Work.**

- `Version: 0.1.0` and the matching `NEWS.md` heading.
- `cran-comments.md` listing the r-actions CI legs as test environments.
- `urlchecker::url_check()` and `spelling::spell_check_package()` clean.

**Exit criteria.**

- Every item of design §12 holds.
- A full-profile run is green on the merge commit.

**Design.** [§12](design.md#12-acceptance-criteria-for-v010).

## Stage 11 — Review

**Issue.** [#13](https://github.com/pedrobtz/zugeo/issues/13), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zugeo/issues/1). No pull request closes it.

**CI.** `full`, always.

**Goal.** The release candidate has been reviewed twice and every
blocking finding fixed.

**Work.**

1. Critical review with `pkg-critical-review`; blocking and required
   findings become sub-issues of this issue, each closed by a pull
   request.
2. CRAN review with `pkg-cran-review`, after those fixes; every FAIL
   and WARN resolved.

**Exit criteria.**

- Every blocking and required review issue closed.
- The `pkg-cran-review` table clean; `NEWS.md` reflects any
  user-visible fix.
- A full-profile run green on the default branch, whose head becomes
  the release commit.

**Design.** None.

## After 0.1.0

- [§14](design.md#14-later-versions-in-the-order-they-are-expected):
  every item, in its order there; none is needed for the first release.
- [§6.9](design.md#69-geoparquet): if `qio` 0.2.0 is not on CRAN when
  Stage 8 closes (D12).

## Blocking open questions

- [§15](design.md#15-open-questions) Q1 blocks Stage 2: whether
  zuarrow hands a dense union to a registered handler. Asked in
  [pedrobtz/zuarrow#171](https://github.com/pedrobtz/zuarrow/issues/171)
  on 2026-11-06, with zugeo's preference that zuarrow does it.
- Q2, Q5, Q8 and Q11 (WKT printing precision, found in Stage 0) are
  answered in Stage 3.
- Q9 is answered in Stage 5.
- Q10 blocks Stage 6: whether `geo_nearest()`, which `geoops` also
  exports, is renamed.
- Q4 blocks Stage 7: whether `qio` or zugeo owns the `geo` key.
