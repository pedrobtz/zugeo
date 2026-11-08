# RFC 0071: `zugeo`, GeoArrow columns in R, exact or an error

Adopted from [RFC 0071](https://github.com/pedrobtz/packages/blob/e9dac6b12d62b967df18c4eeb01927e7c0246866/rfcs/not-started/0071-zugeo-geoarrow-columns.md)
on 2026-11-05. This file is the single source of truth for the design;
the RFC is now a pointer here. Amended on adoption with five items from
a second survey (Julia, and Python, Rust and Go libraries §1.5 had not
covered): §1.6, D14 to D17.

- **Status:** Proposed. Merging this file adopts the design as the starting
  point for the package's own `.agents/design.md`. Each decision in section
  13 stays the maintainer's until the package repository records it.
  GeoParquet (§6.9) is gated on `qio` 0.1.2 (D23; first planned for 0.2.0), and on `zuarrow` reading a union storage type under a registered
  extension name (§15, Q1).
- **Date:** 2026-11-04.
- **Packages:** `zugeo` (not yet created; crandb returns `not_found` and
  there is no `pedrobtz/zugeo` repository, both checked on 2026-11-04).
  `Imports: zuarrow, zujson`; `LinkingTo: zufast` (D18). `Suggests: testthat
  (>= 3.0.0), withr, qio`. No package outside the family appears in
  `DESCRIPTION` (D3): `sf`, `wk`, `geos`, `s2`, `geoarrow`, `nanoarrow`,
  `arrow` and `duckdb` are CI-only oracles, as in zuarrow §9. Vendors
  `geoarrow-c` and the nanoarrow core it builds on (both Apache-2.0);
  zugeo's own code takes MIT.
- **Source:** the grant description of 2026-11-04 for
  `geoarrowrs` ("Native GeoArrow Computation Engine in R", lead Josiah
  Parry, $5,000), which asked what the `zu*` family could offer instead;
  the GeoArrow specification at tag `v0.2.0` (`005d02d`): `format.md` and
  `extension-types.md`; `geoarrow-c` at `b3db89f` (2026-10-21); GeoParquet
  `v1.1.0` and `v2.0.0-rc.1` (2026-07-19); `geoarrow-data` `v0.2.0`;
  `flatbush` `v4.7.0` and `kdbush` `v4.1.0` (ISC); the `geo-index` and
  `geoarrowrs` READMEs; the survey of 2026-11-05 of GeoArrow-adjacent
  libraries in Python, Go, Rust, JavaScript and C (§1.5); zuarrow's
  design document; qio's `.agents/TYPES.md`,
  `carquet.md` and `plan.md`; zujson's `NAMESPACE`; crandb. Section 17
  lists each. Nothing has been built.

## 1. What zugeo is

`zugeo` makes GeoArrow a first-class column type in R. GeoArrow is the
Apache Arrow extension that stores points, lines and polygons as nested
lists of coordinates (the native encodings) or as well-known binary and
text (the serialised encodings), with the coordinate reference system
(CRS) and the edge interpretation in the extension metadata. DuckDB,
GDAL, pyarrow, GeoPandas, Apache Sedona and geoarrow-rs all produce and
consume it.

zugeo does four things:

1. **Registers every `geoarrow.*` extension name with `zuarrow`**, so a
   geometry column from DuckDB, an IPC file or a Spark result arrives as
   a geometry vector instead of nested lists, and goes back out with its
   metadata byte for byte.
2. **Keeps geometries in Arrow memory** as a `geo_vctr`: an R vector of
   row indices over one or more Arrow arrays, which subsets cheaply.
   It leaves as WKB or WKT, the encodings every R spatial package
   reads, on request and never implicitly.
3. **Computes over the coordinate buffers directly**: bounding boxes,
   coordinate counts, geometry types, Hilbert keys and spatial sorting,
   with no per-feature R object and no GEOS round trip.
4. **Builds packed spatial indexes**: a static R-tree over boxes and a
   static k-d tree over points, in the flatbush and kdbush byte formats,
   so an index can be saved, memory-mapped later, and read unchanged by
   `geo-index` in Rust and Python and by flatbush in JavaScript.

With `qio` 0.2.0 it also reads and writes GeoParquet, both the 1.x
`geo` metadata over WKB columns and the 2.0 native Parquet `GEOMETRY`
and `GEOGRAPHY` types, with row-group pruning by bounding box.

The rule that governs every conversion is zuarrow's: **a value crosses
exactly or the call errors.** A CRS is never invented, guessed or
dropped. An edge interpretation R cannot represent is never silently
read as planar. A layout change that does not change a value (separated
to interleaved coordinates, WKB to native) is free; anything that would
change a value is an error naming the column, unless the caller lowers
the bar.

The one-line statement that governs every decision below:

> **GeoArrow in and out of R with its CRS and edges intact, fast bounds,
> sorting and indexes over the buffers, no system library, and no silent
> loss.**

### 1.1 What zugeo is not

- **Not a geometry engine.** No overlay, buffer, predicate beyond box
  intersection, distance beyond box and point distance, validity repair
  or DE-9IM. GEOS (through `geos` or `sf`) and S2 (through `s2`) do
  those, and zugeo hands them WKB, which each of them reads in one
  call. Within the family, `zuclip` (RFC 0025) does polygon
  booleans and offsets and `zucdt` (RFC 0030) does triangulation; both
  take zugeo's buffers through its C table (§7) in a later version.
- **Not a projection library.** zugeo stores, compares and carries a
  CRS. It never transforms coordinates and never resolves an authority
  code to a definition, because both need PROJ and its database.
- **Not an `sf` replacement.** There is no `mask_sf()` and no `st_*`
  method masking (D9). zugeo never calls `sf`. The bridge is WKB and
  a CRS string, which `sf::st_as_sfc()` and `sf::st_crs()` take (§6.6).
- **Not a file-format zoo.** No Shapefile, FlatGeobuf, GeoPackage or
  GeoJSON reader in v0.1.0. GeoJSON is §14, through `zujson`.
- **Not a query engine.** DuckDB's spatial extension is the answer for
  SQL over geometries; zugeo's job there is that the column survives
  the trip both ways.

### 1.2 Where it sits among existing packages

| Package | What it is | Geometry storage | System libraries |
| --- | --- | --- | --- |
| `sf` 1.1-3 | I/O, GEOS, S2, PROJ | R lists | GDAL, GEOS, PROJ |
| `wk` 0.9.5 | handler protocol, WKB, WKT, xy | raw lists, records | none |
| `geos` 0.2.5 | GEOS binding over `libgeos` | GEOS pointers | none (vendored) |
| `s2` 1.1.13 | S2 binding | S2 pointers | cmake, OpenSSL, Abseil |
| `geoarrow` 0.4.4 | GeoArrow over `nanoarrow` | Arrow arrays | none |
| `geoarrowrs` | geoarrow-rs over extendr | Arrow arrays | Rust toolchain |
| `sfarrow` 0.4.1 | GeoParquet 0.x through `arrow` | `sf` | libarrow |

Versions are crandb's on 2026-11-04. `geoarrowrs` is not on CRAN; its
README lists triangulation, Voronoi, length, area, distance,
simplification, bounding boxes and affine operations, and says "Note
that you need Rust to install it." The grant would complete its engine,
add R-tree and k-d tree indexes, `mask_sf()`, GeoParquet sorting,
bounding-box covering columns and PROJJSON persistence, and submit it to
CRAN.

The nearest neighbour is `geoarrow` 0.4.4, Dewey Dunnington's binding of
the same `geoarrow-c` that zugeo vendors. It is good, and §1.3 says
honestly why the family still wants zugeo.

### 1.3 The admission test, applied honestly

`base-layer-candidates.md` §2 asks four things.

1. **A well-specified format with a reference.** Passes. GeoArrow 0.2 is
   two short documents, `geoarrow-c` is the C reference, and the
   `geoarrow-data` files plus pyarrow and DuckDB are the oracles (§9).
2. **Vendorable permissive code or a small specification.** Passes.
   `geoarrow-c` is Apache-2.0, about 550 KB of C and headers without its
   tests, 182 KB of which is `fast_float.h`. The packed indexes are
   about 400 lines of algorithm each, written in C from flatbush and
   kdbush (ISC).
3. **Two siblings that would call it.** Passes in part. `qio` needs it
   for GeoParquet (its `TYPES.md` defers "geospatial interpretation" to
   v0.2.0 and to "downstream packages"), and `zuarrow` gains a registry
   consumer. `zuclip` and `zucdt` would take its buffers but have no
   repositories. `quak` and `zuspark` would carry geometry columns from
   DuckDB and Spark without asking.
4. **A real weakness in base R.** Passes. R has no geometry column type
   that stays in Arrow memory without `nanoarrow`, and the family has
   chosen `zuarrow` over `nanoarrow` (zuarrow §3: "not a dependency,
   not even `Suggests`").

The honest weakness is point 4's reason. `geoarrow` 0.4.4 already turns
GeoArrow into R vectors and back. What it cannot do is sit on
`zuarrow`'s registry, so that `arrow_read()` and `arrow_to_r()` produce
geometry vectors under the family's exactness rule, and it has no
spatial index, no Hilbert sort and no GeoParquet path. A zuarrow
registration that delegates to `geoarrow` is the cheap alternative, and
§13's D1 records why it is not chosen: it would bring `nanoarrow` back
as a hard dependency through the side door.

### 1.4 Against the grant, item by item

| Grant item | zugeo's answer | Where |
| --- | --- | --- |
| GeoArrow-native engine | Arrow-memory vectors, bounds, sort | §6.1, §6.7 |
| Parallelised | no threads in v0.1.0; buffer kernels are memory-bound | D11 |
| No system dependencies | none; no Rust, no cmake | §7 |
| Persistent R-tree | flatbush-format packed R-tree, saved as raw bytes | §6.8 |
| Persistent k-d tree | kdbush-format packed k-d tree | §6.8 |
| Spatial sorting | Hilbert order on box centres, `geo_sort()` | §6.7 |
| `mask_sf()` drop-in | declined; WKB is the bridge | D9 |
| GeoParquet spatial sort | `geo_write_parquet(sort = "hilbert")` | §6.9 |
| Bbox covering columns | read in 1.1; written on request | §6.9, D10 |
| PROJJSON CRS | carried exactly; never invented | §6.4 |
| Lossless across tools | the exactness rule plus four oracles | §6.3, §9 |
| CRAN release | yes, `CRAN intent` `Planned` | §15, Q6 |

The bounding-box covering column is the one item the specification has
moved past. GeoParquet `v2.0.0-rc.1` "Removed the `covering` / `bbox`
column mechanism — the native types' built-in row-group statistics do
this job more efficiently". zugeo reads it in 1.1 files and does not
write it by default (D10).

### 1.5 What other ecosystems do

A survey on 2026-11-05 of the libraries nearest to zugeo outside R
decided four of §2's v0.1.0 items and most of §14.

| Library | Language | Taken from it |
| --- | --- | --- |
| `geoarrow-pyarrow` | Python | extension registration that keeps the CRS |
| `geoarrow-rs` | Rust, Python, JS | buffer kernels; FlatGeobuf, GeoJSON (§14) |
| `shapely` 2 | Python | flat coordinates (§6.10); bulk queries (§6.8) |
| `geopandas` | Python | `hilbert_distance()`; bbox-filtered Parquet reads |
| `geoparquet-io` | Python | Hilbert sort, checks; grid partitions (§14) |
| `gpq` | Go | GeoParquet validation (§6.11) |
| `orb`, `go-geom` | Go | EWKB, hex WKB (§6.6); vector tiles (§14) |
| `simplefeatures` | Go | nothing: a full engine, which §1.1 declines |
| DuckDB spatial | C++ | `ST_Hilbert` oracle (§6.7); tile functions (§14) |
| SedonaDB | Rust | box joins on an index (§6.8); the engine itself declined |
| `geoarrow-js` | TypeScript | its rule: only kernels on the binary layout |
| FlatGeobuf | C++, others | its index is §6.8's packed R-tree (§14) |

Every library §14 would vendor is permissive: GeographicLib's
`geodesic.c` (MIT, one 73 KB file), `earcut.hpp` (ISC), H3 4.5.0
(Apache-2.0, plain C), FlatGeobuf's `packedrtree.cpp` (BSD-2). GEOS is
LGPL and stays out.

### 1.6 The second survey

A survey on 2026-11-05 of the Julia ecosystem (JuliaGeo, JuliaEarth) and
of Python, Rust and Go libraries §1.5 left out added five v0.1.0 items.

| Library | Language | Taken from it |
| --- | --- | --- |
| `pyproj` `CRS.equals()` | Python | CRS comparison levels (§6.4, D14) |
| GeometryOps.jl, `geozero` | Julia, Rust | one coordinate visitor (§4, D15) |
| Extents.jl | Julia | `geo_extent` with set operations (§6.7, D16) |
| GeometryOps.jl dual DFS | Julia | joining two indexes (§6.8) |
| `pyogrio` `read_info()` | Python | `geo_parquet_info()` (§6.9) |

Also considered and placed in §14: spatial weights from the indexes
(`libpysal` `Graph`), Morton, geohash and quadbin keys
(`dask-geopandas`, `quadbin`), an STR loader and nearest-neighbour
search with a caller's distance (`geo-index`, SortTileRecursiveTree.jl),
and `tg` (MIT, one C file) for point-in-polygon in a separate package.
Declined: GeoInterface.jl-style adapters that `sf` or `wk` would
register, and PROJ or GEOS in `Suggests` (both D3); S2, A5 and H3 in
the core. `polars-st` is LGPL because it links GEOS, the outcome §1.1
avoids.

## 2. Scope

**In v0.1.0:**

- Every extension name in GeoArrow 0.2: `geoarrow.point`, `.linestring`,
  `.polygon`, `.multipoint`, `.multilinestring`, `.multipolygon`,
  `.geometry`, `.geometrycollection`, `.box`, `.wkb` and `.wkt`, in both
  coordinate layouts (separated `struct` and interleaved
  `fixed_size_list`), XY, XYZ, XYM and XYZM, with `list` and
  `large_list` offsets and the binary and string view storage types.
- Extension metadata: `crs` in all four `crs_type` forms and absent;
  `edges` in all six values and absent.
- Registration with `zuarrow` for reading (`to`) and writing (`from`).
- `geo_vctr`, the R vector class (§6.1), with `[`, `length()`, `c()`,
  `format()` as WKT, `is.na()` and `as.data.frame()`.
- Conversions between encodings: `geo_as_wkb()`, `geo_as_wkt()`,
  `geo_as_native()`, and `geo_vctr()` from WKB, EWKB, hex WKB or WKT,
  which is how `sf`, `geos`, `s2` and database results come in and go
  out (§6.6).
- Coordinates as columns: `geo_coords()` and `geo_from_coords()`, with
  `geo_points()` for the common case (§6.10).
- Kernels over buffers, all through one coordinate visitor (§4):
  `geo_box()` per row and in aggregate, `geo_types()`, `geo_dims()`,
  `geo_n_coords()`, `geo_hilbert()`, `geo_sort()`.
- `geo_extent`, the box vector that `geo_box()` returns and index
  queries take, with `geo_extent_union()`, `geo_extent_intersection()`
  and `geo_extent_intersects()` (§6.7).
- Packed indexes: `geo_rtree()` and `geo_kdtree()`, box and radius
  queries, k nearest neighbours by box distance, bulk box joins that
  return candidate pairs, of a vector against an index or of two
  indexes, `geo_index_raw()` and `geo_index_from_raw()` for
  persistence (§6.8).
- Validation: `geo_validate()` on a vector and on a GeoParquet file's
  metadata against its data (§6.11).
- CRS helpers: `geo_crs()`, `geo_set_crs()`, `geo_crs_equal()` at
  three levels (§6.4).

**In v0.1.0, gated on `qio` 0.2.0:**

- `geo_read_parquet()`, `geo_write_parquet()` and `geo_parquet_info()`
  (§6.9). If `qio` 0.2.0
  is not on CRAN when the rest is ready, these move to 0.2.0 rather than
  hold the release (D12).

**Later, when asked (§14):** a C table, GeoJSON through `zujson`,
geodesic measures through GeographicLib, exact planar kernels,
FlatGeobuf, vector tiles through `zuproto`, spherical bounds,
memory-mapped indexes, threads, `zuclip` and `zucdt` on buffers.

**Never:** coordinate transformation beyond web Mercator for tiles,
authority-code resolution, overlay and predicates beyond boxes, curves,
rasters, `sf` masking, a query engine.

## 3. Position in the `zu*` family

| | zugeo |
| --- | --- |
| Role | format; provider of a C table after v0.1.0 (§14) |
| R prefix | `geo_` (D7) |
| Info function | `zugeo_info()`: vendored versions, GeoArrow version |
| Root condition class | `zugeo_error` |
| Public C prefix | `zugeo_` after v0.1.0; internal `zgo_` / `ZGO_` |
| From C | not in v0.1.0 (§14) |
| Hides symbols | yes, from Stage 0 (R3) |
| Vendored code | `geoarrow-c`, nanoarrow core (§7) |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

The `zgo_` prefix and the `GeoArrow` and `ArrowArray` namespaces are
checked in Stage 0 with `nm` over every installed `zu*` package and
over `geoarrow`, `nanoarrow` and `arrow`, as zuarrow did for `zar_`.

**Relationships, as decided rather than as hoped:**

- **`zuarrow`** (RFC 0041): `Imports`. zugeo registers each `geoarrow.*`
  name in `.onLoad()` through zuarrow §6.10. The extension name takes
  precedence over the storage type, which is what lets a dense union
  reach zugeo's handler for `geoarrow.geometry`; zuarrow §6.2 lists
  unions as "always an error" today, so Q1 asks for that exception.
  *2026-11-06:* granted by
  [pedrobtz/zuarrow#172](https://github.com/pedrobtz/zuarrow/pull/172).
  Handles are zuarrow's, which are nanoarrow's layout (zuarrow D6), so
  `geoarrow-c` reads them directly.
- **`zufast`**: `LinkingTo`, header-only, on CRAN. `geoarrow-c`'s two
  number functions are reimplemented over it by a local patch (D18), so
  WKT prints the shortest round-trip digits and parses correctly
  rounded on every platform.
- **`zujson`**: `Imports`, for parsing and writing extension metadata,
  the GeoParquet `geo` key and PROJJSON. Every metadata string goes
  through `json_parse()` and `json_write()`; zugeo has no JSON code.
- **Outside packages**: none in `DESCRIPTION` (D3). `sf`, `wk`, `geos`,
  `s2`, `geoarrow`, `nanoarrow`, `arrow` and `duckdb` are installed by
  the `oracles` workflow and used only in `tests/testthat/test-ci-*.R`,
  which `.Rbuildignore` keeps out of the tarball, as zuarrow does.
- **`qio`**: `Suggests`. Its v0.1.0 reads `GEOMETRY` and `GEOGRAPHY` as
  raw WKB bytes and reports `crs` and the edge algorithm in `schema()`;
  carquet already exposes "footer key/value pairs" and "geospatial
  bounds" (qio `carquet.md`). zugeo needs from `qio` 0.2.0: those bounds
  per row group, writing the native geospatial logical types, and a
  column read as a `zuarrow` stream. The last is already on zuarrow's
  §14 list.
- **`zuclip`** (RFC 0025) and **`zucdt`** (RFC 0030): consumers through
  the C table, later. Both RFCs list `wk` handlers as a later item;
  zugeo's buffers give them geometry input without `wk`.
- **`quak`** and **`zuspark`** (RFC 0070): carriers of whatever geometry
  columns DuckDB and Spark export as GeoArrow; which options produce
  them is unverified (§17). Neither package changes: zuarrow's registry
  does the work.
- **`zutable`** (RFC 0036): a `geo_vctr` is a column like any other; a
  locked schema may name `geoarrow.*` types.
- **`zukomp`**: not a dependency. Compression in IPC and Parquet is
  zuarrow's and qio's.

## 4. Architecture

Four layers, bottom up:

1. **Vendored C.** `geoarrow-c` for schema views, array views, the
   native, WKB and WKT readers and writers, and the `box` and
   `format_wkt` kernels. Its nanoarrow core is a separate copy under
   `NANOARROW_NAMESPACE=ZugeoNanoarrow`, so it never collides with
   zuarrow's copy or with a loaded `nanoarrow` (D2).
2. **zugeo's C.** The Hilbert curve, the packed R-tree and k-d tree, the
   coordinate-count and type kernels, and the `geo_vctr` chunk
   lookup. No call back into R from inside a loop. Every kernel that
   walks coordinates is a reduction over one visitor (D15): a traversal
   of each array view that calls `begin_feature`, `begin_part`,
   `begin_ring`, `coords` (a run of XY[ZM] values) and the matching
   `end_*`, with a per-feature and an aggregate result. Box, counts,
   types, dims, Hilbert centres and `geo_validate()` are each a few
   callbacks over it, and §14's affine, area, length and GeoJSON
   writers reuse it. `geoarrow-c`'s own visitor drives it for WKB and
   WKT; the native layouts are walked directly over the buffers.
3. **The registry glue.** One `to` and one `from` per extension name,
   written in R over C entry points, registered in `.onLoad()`.
4. **The R API.** `geo_*` functions, S3 methods for `geo_vctr`, and
   the GeoParquet functions over `qio`.

The data path from DuckDB to `sf`, with no copy until the last step.
DuckDB and `sf` are the user's packages, not zugeo's:

```text
duckdb result (ArrowArrayStream)
  -> zuarrow::arrow_to_r()             registry: geoarrow.wkb -> zugeo
  -> geo_vctr (indices + array handle) cheap [, sort, box, index
  -> geo_as_wkb(), geo_crs_text()      list of raw, one CRS string
  -> sf::st_as_sfc(wkb, crs = text)    sf parses: one pass, R lists
```

## 5. Public R API (v0.1.0 shape)

```r
# vectors
geo_vctr(x, crs = NULL, edges = NULL)  # from WKB, WKT or Arrow
is_geo_vctr(x)
geo_as_wkb(x); geo_as_wkt(x); geo_as_native(x, layout = "separated")
geo_type_of(x)                         # the Arrow-level description;
                                       # a named list of them for a struct

# coordinates as columns
geo_coords(x)                          # x, y[, z, m], feature, part, ring
geo_from_coords(coords, type)          # the reverse
geo_points(x, y, z = NULL, m = NULL)

# metadata
geo_crs(x, crs_type = NULL)            # also makes one from a string
geo_set_crs(x, crs, crs_type = NULL)
geo_crs_text(x)                        # one string for other packages
geo_crs_equal(x, y, level = "identical")  # or "structural", "authority"
geo_edges(x); geo_set_edges(x, edges)

# extents
geo_extent(xmin, ymin, xmax, ymax, zmin = NULL, zmax = NULL,
           mmin = NULL, mmax = NULL)
geo_extent_union(e); geo_extent_intersection(e, f)
geo_extent_intersects(e, f)            # logical, recycled

# kernels
geo_box(x)                             # geo_extent, one per row
geo_box_all(x)                         # geo_extent of length one
geo_types(x); geo_dims(x); geo_n_coords(x)
geo_hilbert(x, extent = NULL)          # uint32 keys as double
geo_sort(x, by = "hilbert")            # permutation

# indexes
geo_rtree(x, node_size = 16L)
geo_kdtree(x, node_size = 64L)         # points only
geo_query_box(index, extent)           # a geo_extent
geo_query_radius(index, x, y, r)       # k-d tree
geo_query_nearest(index, x, y, k = 1L, max_distance = Inf)
geo_join_box(index, y)                 # y a geo_vctr, geo_extent or index;
                                       # data frame of candidate pairs
geo_index_raw(index); geo_index_from_raw(raw)

# GeoParquet, with qio 0.2.0
geo_read_parquet(path, bbox = NULL, columns = NULL, lossy = "error")
geo_write_parquet(x, path, sort = "hilbert", version = "2.0",
                  covering = FALSE)
geo_parquet_info(path)                 # metadata only; reads no rows

# validation
geo_validate(x)                        # data frame of findings
geo_validate_parquet(path, metadata_only = FALSE)

zugeo_info()
```

### Results

A `geo_vctr` is what every reading path returns. Kernels return plain
R vectors and data frames. Indexes return a `zugeo_index` object whose
only state is the raw vector of §6.8. Queries return 1-based integer
row positions into the vector the index was built from.

## 6. Semantics

### 6.1 `geo_vctr`

A `geo_vctr` is an integer vector of row positions with three
attributes: `chunks`, a list of zuarrow array handles; `schema`, one
zuarrow schema handle carrying the extension name and metadata; and the
class `geo_vctr`. Element `i` refers to row
`x[i]` of the concatenated chunks. This is the same idea as
`geoarrow`'s `geoarrow_vctr`, which is a `nanoarrow` vector over a
stream, so the two can convert to each other through the C Data
Interface in a CI test.

- `[`, `rev()` and `geo_sort()` permute the integers; no buffer is
  touched.
- `c()` of two `geo_vctr` with equal schemas appends chunks; with
  different CRS or edges it is a `zugeo_crs_error` (§6.4).
- Export through zuarrow (`from`) materialises the rows in order into
  one array of the schema's type. A vector whose positions are
  `seq_len(n)` over one chunk exports that chunk unchanged.
- `NA` positions are null geometries. Arrow allows nulls only at the
  outer level, so this is the only kind there is.

*Decided 2026-11-06 (Stage 2):*

- **Representation.** Positions are 1-based integers into the
  concatenated chunks; the attribute `starts` holds each chunk's first
  row, so a position maps to a chunk and row without scanning. A vector
  is limited to 2^31 - 1 rows for now, and `c()` beyond that is an
  error.
- **Union nulls.** A union has no validity bitmap, so an element is null
  when the child element it points to is. Gathering writes a null as a
  null element of that child, or of the first child for an `NA`
  position.
- **`c()` of other layouts.** Equal schemas (zuarrow's `arrow_equal()`,
  metadata included) append chunks; a different CRS or edge type is a
  `zugeo_crs_error`; any other difference, such as separated against
  interleaved, is a `zugeo_layout_error` until Stage 3's conversions.
- **No assignment.** `[<-` and `[[<-` are errors; `length<-` pads with
  `NA`.
- **`format()`** writes WKT through `geoarrow-c`'s WKT writer, with
  `max_bytes` (1000 by default) truncating each element, and prints
  numbers as that writer does until D18 lands in Stage 3. Nulls format
  as `<null>`; `as.character()` gives `NA`.
- **`geo_vctr()`** takes an array handle in this stage; WKB, WKT and
  coordinate inputs are Stage 3's.

### 6.2 Types and layouts

GeoArrow allows several layouts for one extension name. zugeo reads all
of them and writes one per name unless told otherwise.

| Read | Written by default |
| --- | --- |
| separated or interleaved coordinates | separated, as `format.md` advises |
| `list` or `large_list` offsets | `list`; `large_list` when 32 bits overflow |
| `binary`, `large_binary`, `binary_view` (WKB) | `binary` |
| `utf8`, `large_utf8`, `utf8_view` (WKT) | `utf8` |
| `geoarrow.geometry` (dense union) | never written in v0.1.0 (D8) |
| `geoarrow.box` with `xmin > xmax` | kept as given |

A mixed column from R (points and polygons together) is written as WKB,
and a column of polygons and multipolygons as `geoarrow.multipolygon`,
which `format.md` recommends "over a geometry array if possible". The
union type is read, never produced, until zuarrow writes unions (its §2
lists that as later).

### 6.3 Exact or error

zugeo applies zuarrow's `lossy` policy (`"error"`, `"warn"`, `"allow"`)
to the cases below and to nothing else. Every other conversion is
exact.

- **Edges.** A `geo_vctr` keeps every edge type untouched, and so does
  every GeoArrow and GeoParquet export. Bare WKB and WKT have no place
  for edges, so `geo_as_wkb()` and `geo_as_wkt()` on a column with
  non-planar edges are a `zugeo_edges_error` naming the edge type. The
  specification's own exception applies: a column with no edges
  (points, multipoints, empties) converts freely.
- **CRS.** Bare WKB and WKT have no place for a CRS either. Both
  results carry it as the attribute `crs` in its original form, and
  `geo_crs_text()` gives it as one string. Never resolved, never
  dropped (§6.4).
- **Dimensions.** Z and M pass through every encoding, ISO WKB
  included.
  `geo_box()` reports Z and M ranges when present.
- **Text.** WKT to native is a parse; native to WKT prints the shortest
  representation that reads back to the same double. A round trip
  through WKT is therefore exact, and a test proves it on every
  coordinate in the `geoarrow-data` files. *2026-11-06:*
  `geoarrow-c`'s printer does not do this as vendored; Q11.
- **Empties.** An empty point is `POINT (NaN NaN)` per `format.md`, and
  stays `NaN NaN`, never null.
- **Bad layouts.** A null inside a ring, an unclosed ring in a polygon
  claimed valid, or a child carrying extension metadata is a
  `zugeo_layout_error` at read, because the specification forbids it.
  Unclosed rings are reported, not repaired.

*Decided 2026-11-07 (Stage 4):*

- **Where the policy applies.** `geo_as_wkb()` and `geo_as_wkt()` take
  `lossy` (`"error"`, `"warn"`, `"allow"`), the one place a conversion
  can lose something today. A column has edges when any line or ring, at
  any depth, has two vertices or more; points, multipoints, empties,
  nulls and collections of points convert freely. Under `"warn"` the
  warning is a `zugeo_edges_warning`; the condition carries `edges`.
  Reading through zuarrow loses nothing, so its `lossy` reaches the
  handler with nothing to apply; `geo_box()` on non-planar edges joins
  in Stage 5.
- **Nulls inside geometries** are a `zugeo_layout_error` when a column
  becomes a `geo_vctr`, from any level below the outer one; a union's
  outer nulls are its children's, so its check starts a level down.
  "An unclosed ring in a polygon claimed valid" has no claim to check
  in GeoArrow metadata, so unclosed rings are reported by
  `geo_validate()` (§6.11, Stage 5), never refused at read.
- **Coordinates keep the CRS and edges** as the attributes `crs` and
  `edges` of `geo_coords()`'s data frame, which `geo_from_coords()`
  takes back by default, so that route drops neither.

### 6.4 CRS

The specification allows a CRS as a PROJJSON object, a WKT2:2019 string,
an `AUTHORITY:CODE` string or an opaque SRID, tagged by `crs_type`, or
absent. zugeo stores the CRS exactly as given, as a `zugeo_crs` object
holding the parsed JSON or the string and the `crs_type`.

- **Equality.** `geo_crs_equal()` has three levels, after `pyproj`'s
  `is_exact_same()` and `equals()` (D14). None calls PROJ.
  - `"identical"`, the default and the one `c()` and every check
    inside zugeo use: true when both are absent, when the two strings
    are byte-identical, or when two PROJJSON objects are equal after
    `zujson` parsing, ignoring key order. Anything else is false.
  - `"structural"`: PROJJSON compared after dropping the members that
    do not change coordinates (`$schema`, `name`, `remarks`, `usage`,
    `scope`, `area`, `bbox`) and normalising numbers. A WKT2 or
    `AUTHORITY:CODE` string on either side gives `NA`.
  - `"authority"`: true when both carry the same authority and code,
    whether as an `AUTHORITY:CODE` string or as a PROJJSON `id`
    member, case-insensitive in the authority. A short built-in alias
    table adds the pairs that differ only in axis order, starting with
    `OGC:CRS84` and `EPSG:4326`; axis order cannot differ inside
    GeoArrow (below), so for zugeo they are one CRS. Either side
    without an authority and code gives `NA`.

  `NA` means zugeo cannot tell without PROJ, never that the two
  differ. Two CRS that PROJ would call equivalent but that no level
  can see as equal are not equal to zugeo; that is the price of having
  no PROJ, and the error message says so.
- **From other packages.** zugeo calls no other package, so a CRS
  arrives as the caller's string: `geo_vctr(wkb, crs = text)`. A string
  that parses as a JSON object is stored as PROJJSON, one that starts
  with a WKT2 keyword as `"wkt2:2019"`, one of the form `AUTH:CODE` as
  `"authority_code"`, and anything else with no `crs_type`, as the
  specification asks. It never writes an authority code it did not
  receive.
- **To other packages.** `geo_crs_text()` returns the stored form as
  one string: PROJJSON as compact JSON, the rest unchanged. PROJ reads
  all three forms as user input, which is what `sf::st_crs()` passes
  it; the CI oracle checks that (Q5).
- **To GeoParquet 2.0.** The `geo` key's `crs` "must be inline PROJJSON
  (or `null`)". A column whose CRS is not PROJJSON is written with the
  native Parquet `crs` property in the form it has and without the
  `geo` key's `crs`, which the 2.0 release notes allow ("Writers that
  cannot readily generate PROJJSON ... are encouraged to write plain
  native Parquet with an `<authority>:<code>` CRS").
- **Axis order** is always longitude then latitude, easting then
  northing, as the specification states, whatever the CRS says.

### 6.5 Registration with zuarrow

zugeo registers twelve keys at load: the eleven extension names and the
R class `geo_vctr` for export. Every registration declares `exact =
TRUE`. The `to` handler takes three arguments and receives the caller's
`lossy`, so `arrow_to_r(stream, lossy = "warn")` reaches §6.3.

An `arrow_to_r(to = list(geom = "wkb"))` prototype asks for the WKB
encoding at read, which zuarrow §6.10 already supports. Without zugeo
loaded, the same columns read as their storage types with the extension
attributes, exactly as zuarrow §6.6 does today, and a later
`geo_vctr()` on such a column recovers the geometry from those
attributes.

### 6.6 Interchange with other packages

WKB is the interchange format, because every R spatial package reads
and writes it and none of them has to be a dependency to do so.

- **Out.** `geo_as_wkb()` returns a plain list of raw vectors, ISO WKB,
  little-endian, `NULL` for a null geometry, with the `crs` attribute.
  `sf::st_as_sfc()`, `geos::geos_read_wkb()` and
  `s2::s2_geog_from_wkb()` each take such a list directly; the CI
  oracle proves all three on the corpus.
- **In.** `geo_vctr()` takes a list of raw vectors whatever its class,
  so the output of `sf::st_as_binary()`, `wk::as_wkb()` and
  `geos::geos_write_wkb()` all arrive the same way, and a character
  vector as WKT. Both are parsed in C by `geoarrow-c` into native
  buffers with no R object per feature.
  *Decided 2026-11-07 (Stage 3):* WKB is checked by parsing and stored
  as ISO little-endian WKB in a `geoarrow.wkb` column; WKT is checked by
  parsing and stored as given, byte for byte, in a `geoarrow.wkt`
  column. Neither is turned into native buffers until
  `geo_as_native()` asks, because a native type needs one geometry type
  and WKB or WKT input often mixes them. A character vector whose every
  element is hex text is hex WKB; anything else is WKT.
- **Databases.** PostGIS returns EWKB, often as hex text, and DuckDB
  has `ST_AsHEXWKB`; `orb` and `go-geom` read both for that reason.
  `geo_vctr()` accepts EWKB and hex WKB as well. An EWKB SRID becomes a
  CRS of `crs_type = "srid"` unless `crs =` is given, and differing
  SRIDs in one column are a `zugeo_crs_error`. *Decided 2026-11-06
  (Q8):* `geoarrow-c` reads EWKB but discards the SRID without a trace
  (`wkb_reader.c`: "We ignore this"), so zugeo reads each feature's
  header itself first, in C: the SRID of the outer geometry and of any
  nested one, which must agree. Then it hands the unchanged bytes to
  `geoarrow-c`.
- **Cost.** WKB is one copy each way, where `wk`'s handler protocol
  would stream without one. §14 records how that protocol can be
  reached later without adding `wk` to `DESCRIPTION`.

### 6.7 Bounds, Hilbert keys and sorting

`geo_box()` is the per-row box reduction over §4's visitor;
`geo_box_all()` is the aggregate one. Both equal `geoarrow-c`'s `box`
and `box_agg` kernels, which a test checks on the corpus. Bounds are
planar.

Both return a `geo_extent` (D16), after Extents.jl: a record vector of
`xmin`, `ymin`, `xmax`, `ymax` and, when present, `zmin`, `zmax`,
`mmin`, `mmax`, with `[`, `c()`, `length()`, `format()` and
`as.data.frame()`, and the `crs` and `edges` of its source. It is what
index queries take and what `geo_parquet_info()` reports, so boxes have
one type everywhere. `geo_extent_union()` reduces to one extent,
`geo_extent_intersection()` and `geo_extent_intersects()` recycle
pairwise, and combining extents with unequal CRS is a
`zugeo_crs_error`, as for `c()` of vectors. An empty geometry's box is
all `NaN` and a null's is `NA`; both are disjoint from everything. A
`geoarrow.box` column converts to a `geo_extent` and back exactly,
including `xmin > xmax`, which the specification uses for boxes that
cross the antimeridian; the set operations raise a `zugeo_edges_error`
on such a box rather than misread it, until §14's spherical bounds.
For `spherical` and the ellipsoidal edges
a planar box can be wrong for an edge that bulges past its vertices or
crosses the antimeridian, so on such a column `geo_box()` is a
`zugeo_edges_error` under `"error"` (§14 lists spherical bounds).

`geo_hilbert()` maps each box centre into a 16-bit grid over `extent`
(the aggregate box by default) and returns the 32-bit Hilbert index,
the same function and the same grid flatbush uses, so a zugeo sort and
a flatbush sort agree. Null and empty geometries sort last. DuckDB's
`ST_Hilbert` and geopandas' `hilbert_distance()` compute the same kind
of key; whether their grids agree with flatbush's is Q9, and the
oracle tests record the answer so that a file sorted by zugeo and one
sorted by DuckDB are known to agree or known not to.
`geo_sort()` returns the permutation; `x[geo_sort(x)]` is the sorted
vector.

*Decided 2026-11-07 (Stage 5):*

- **flatbush's arithmetic, not an equivalent.** The grid position is
  `trunc((65535 / size) * (centre - min))`, the size being the range or
  1 when the range is 0, which is `finish()`'s `(sx * (c - min)) | 0`;
  a formula that is equal on paper rounds differently in doubles. The
  key is flatbush's unsigned (it subtracts 2^31 to keep JavaScript
  integers small; the order is the same). Centres outside a given extent
  are clamped onto its edge.
- **One walk for the per-row kernels.** Box, top-level type, dimensions
  and coordinate count come from one visitor pass
  (`src/zgo_kernel.c`). An empty point (`NaN NaN`) has no coordinates;
  a collection's dimensions are its own header's, so `GEOMETRYCOLLECTION
  (POINT M (1 2 3))` is XY with an XYM part, which `geo_validate()`
  reports as `mixed_dimensions`.
- **`geo_box()` takes `lossy`** for non-planar edges on geometries with
  edges, as `geo_as_wkb()` does.
- **`geo_extent`** is a record of numeric bounds with `crs` and `edges`
  attributes; Z and M bounds come in pairs and only when present. Set
  operations compare dimensions both sides have; a box touching
  another intersects it; a disjoint intersection is `NaN`, one with a
  null is `NA`. Combining or comparing extents of different CRS or
  edges is a `zugeo_crs_error`.
- **`geoarrow-c`'s box kernel** is the oracle where it can read the
  layout (`zgo_c_geoarrow_box()`, tests only). It reports XY only, and
  `Inf`/`-Inf` where zugeo has `NA` for nulls and `NaN` for empties.

### 6.8 Packed indexes

Both indexes are immutable and bulk-loaded, and each is one raw vector.

- **R-tree.** Boxes are Hilbert-sorted, packed into nodes of
  `node_size` and stored in flatbush's serialised format version 3:
  the `0xfb` magic byte, the version and array type, node size, item
  count, then the boxes and the indices. Coordinates are `Float64`.
- **k-d tree.** Points only, in kdbush's format, for radius and box
  queries on point clouds.
- **Persistence.** `geo_index_raw()` returns the bytes; writing them
  with `writeBin()` is the persisted index. `geo_index_from_raw()`
  validates the header and the sizes before use. Because the format is
  flatbush's, the same bytes load in `geo-index` (Rust, and Python as
  `geoindex-rs`), which its README calls "compatible with the
  `flatbush` and `kdbush` JavaScript libraries", and in flatbush
  itself. That makes the index a cross-language artifact, which the
  grant's "persistent" asks for.
- **Joins.** `geo_join_box(index, y)` queries every box of `y` against
  the index in one C call and returns a two-column data frame of
  candidate pairs, as `shapely`'s bulk tree query and SedonaDB's joins
  do. When `y` is itself an index, the two trees are descended
  together, pruning every pair of nodes whose boxes are disjoint, as
  GeometryOps.jl's `dual_depth_first_search` does; the result is the
  same set of pairs, cheaper when both sides are large. Refining
  candidates with an exact predicate is GEOS's job.
- *Decided 2026-11-07 (Stage 6):* builds follow flatbush v4.7.0 and
  kdbush v4.1.0 step for step, their sorts included (flatbush's
  quicksort that stops inside a node, kdbush's Floyd-Rivest selection
  with its sampling arithmetic), because the bytes depend on the order:
  on 1 to 70 000 items the bytes equal the libraries' own in node
  (`tools/index-oracle.mjs`, `test-ci-index.R`). Null and empty
  geometries are left out of an index; queries return positions in the
  indexed vector, and an index read from raw bytes numbers its items 1
  to n. One query returns a sorted integer vector, several a data frame
  of `query` and `row`; `geo_query_nearest()` returns `query`, `row` and
  `distance` nearest first. Every node offset and item number read from
  bytes is checked before use, so corrupt bytes are a
  `zugeo_index_error`. The k-d tree takes points only, and nearest
  neighbours are the R-tree's; indexes are little-endian, as flatbush
  writes them. *geo-index's Python package (`geoindex-rs` 0.1.0, the
  only release) builds from arrays but neither reads nor writes bytes*,
  so that leg compares query results over the same boxes, and the
  cross-language claim rests on flatbush and kdbush.
- **Queries** are box intersection, radius (k-d tree), and k nearest
  by box distance. Exact nearest by geometry distance needs a distance
  function, so `geo_query_nearest()` returns box-distance candidates and says
  so in its documentation; refining them is GEOS's or S2's job.

### 6.9 GeoParquet

With `qio` 0.2.0 installed:

- **Reading.** `geo_read_parquet()` reads the `geo` footer key with
  `zujson` when present, the native `GEOMETRY` and `GEOGRAPHY` logical
  types when present, or both, and errors when they disagree on a
  column's CRS or edges. `bbox =` prunes row groups first by the native
  geospatial statistics, then by a 1.1 `covering` column's statistics,
  and then filters rows by box. Geometry columns come back as
  `geo_vctr`, others through qio's own mapping.
- **Writing.** `geo_write_parquet()` writes GeoParquet 2.0 by default:
  WKB in the native `GEOMETRY` type (or `GEOGRAPHY` with an
  `algorithm` for non-planar edges), the `geo` key alongside, rows in
  Hilbert order, and row groups sized so their statistics prune well.
  `version = "1.1"` writes the 1.1 metadata over plain binary, and
  `covering = TRUE` adds the bbox struct column for readers that need
  it. GeoParquet 1.1's native GeoArrow encodings in Parquet are read
  and never written, because 2.0 removed them.
- **Metadata.** `geo_parquet_info()` reads the footer and nothing
  else, as `pyogrio`'s `read_info()` does for OGR sources: row count,
  row groups with their row counts and `geo_extent` from the native
  statistics (or the `covering` column's), and per geometry column the
  encoding, geometry types, CRS, edges and file-level box. It is how a
  caller sees what `bbox =` would prune before reading (D17).
- **Oracles.** DuckDB's spatial extension and GDAL through `sf` read
  every file zugeo writes, in the CI-only tests (§9).

*Decided 2026-11-07 (Stage 7), D23:* built over `qio` 0.1.2 (its
`geospatial_statistics()`, the native types on write, footer pairs and
row-group selection), not 0.2.0, so D12 is not invoked. The signatures
are `geo_read_parquet(path, bbox = NULL, columns = NULL)` and
`geo_write_parquet(x, path, sort = "hilbert", version = "2.0",
row_group_size = 100000L, compression = "zstd")`: the guide's 50,000 to
200,000 rows and its zstd. *2026-11-08 (Review, #31):* `geo_read_parquet()`
also takes `lossy`, as `geo_box()` does: its `bbox` row filter is planar,
so on lines and polygons with non-planar edges it is a `zugeo_edges_error`
unless `lossy` is `"warn"` or `"allow"`. `covering` is not an argument yet, and 1.1's
native encodings are read as a `zugeo_parquet_error`, because both are
nested columns qio cannot write or read until its 0.2.0. The CRS rules
keep D6. A `geo` key must hold PROJJSON, so a CRS given as a code or WKT
is written in the Parquet type alone and the key is left out, as the 2.0
specification advises writers that cannot produce PROJJSON; version 1.1
then raises `zugeo_crs_error`. OGC:CRS84 is written by omitting the key's
`crs`, no CRS as `null` and `srid:0`, and PROJJSON over the Parquet
type's 127 bytes under the footer key `projjson_crs_<column>`. On read,
the key's and the type's CRS disagree only when
`geo_crs_equal(level = "authority")` is `FALSE`: the specification lets
them differ in form (a code beside PROJJSON), so `"identical"`, D14's
level for zugeo's own checks, would reject conformant files. This
comparison of two statements in one file is the one exception to D14;
the key's PROJJSON is kept unless the two are identical. qio 0.1.2 also
reads a native CRS of any length: carquet had cut it to 127 bytes,
which zugeo found on the corpus's inline-PROJJSON files.

### 6.10 Coordinates as columns

`geo_coords()` returns a data frame with one row per vertex: `x`, `y`,
`z` and `m` when present, and the integer columns `feature`, `part` and
`ring` that place each vertex. It is `shapely`'s `to_ragged_array()`
and `geopandas`' `get_coordinates()` in R form, and `sf::st_coordinates()`
in shape. For the separated layout the coordinate columns are copies of
the Arrow buffers, with no parsing.

`geo_from_coords()` is the reverse, with `type` naming the geometry
type, and `geo_points()` builds a point column straight from vectors.
Double vectors are the one interchange every R package reads, so this
is the second route out of zugeo after WKB (§6.6), and the cheaper one
for points.

### 6.11 Validation

`geo_validate()` reports, one row per finding, what `gpq validate`
checks (*decided 2026-11-07, Stage 5:* the issues are `unclosed_ring`,
`short_ring`, `short_linestring`, `non_finite`, `mixed_dimensions`, and
`exterior_clockwise` and `interior_counterclockwise` against RFC 7946's
winding, for information; a declared type is checked against the
values with GeoParquet's `geometry_types`, in Stage 7): rings closed,
ring orientation, a declared geometry type matching the values,
coordinates finite except for empty points, and
dimensions consistent within a feature. It reports and never repairs.

`geo_validate_parquet()`, with `qio` 0.1.2, also checks the `geo` key
against the schema, its `bbox` against the data, the native types'
statistics against the data, and the best practices of the 2.0
distribution guide that can be read from the file: spatial ordering,
row-group sizes, compression. `metadata_only = TRUE` skips the data
scan, as `gpq` does.

*Decided 2026-11-07 (Stage 7):* one row per finding of `column`,
`row_group`, `row`, `issue`, `severity` and `message`. Severity `"error"`
is a break with the specification, mirroring `gpq validate`'s rules and
adding 2.0's (native type present, CRS and edges agreeing, statistics
covering their data); `"warning"` is a geometry finding of
`geo_validate()` (winding only when `orientation` is declared) or the
guide's advice (zstd, row groups over 200,000 rows, row-group boxes that
overlap as unordered data does). PROJJSON is checked to be an object,
not against its JSON schema. *Measured 2026-11-07 (Stage 7):* gpq
v0.24.0 (2024-11) is older than parts of the specification, and the
agreement test asserts each gap where it occurs rather than skip the
file. It predates 1.1's native encodings; its Arrow Go v16 panics on the
`GEOMETRY` and `GEOGRAPHY` logical types, so it reads no 2.0 file; its
WKB decoder is 2D and it rejects the " M" and " ZM" type names, so files
with Z or M fail; and it bounds an empty non-point geometry as (0, 0),
failing the bbox check of every corpus file that has one. Everywhere
else, the 2D `_geo` files, the plain native files and zugeo's 1.1 output,
the two agree.

## 7. Vendored code

| Library | Version | Licence | Used for |
| --- | --- | --- | --- |
| `geoarrow-c` | `b3db89f` (0.2.0-SNAPSHOT) | Apache-2.0 | views, I/O, `box` |
| nanoarrow core | 0.9.0 release, as zuarrow | Apache-2.0 | Arrow helpers |

*Decided 2026-11-06 (Stage 0):* `src/vendor/` is derived by
`tools/derive-vendor`: the commit's archive, checked by SHA-256, run
through upstream's CMake bundler (`GEOARROW_BUNDLE=ON`,
`GEOARROW_NAMESPACE=Zugeo`), with `fast_float` off because it is C++.
Parsing then uses `strtod()`, which R keeps in the C numeric locale.
ryu is off too: its `assert()` calls reached the shared object in the
gctorture build, which ignores `-DNDEBUG`, so WKT numbers print through
`snprintf()` until Q11 is settled. No local patches. *2026-11-06
(Stage 2):* the nanoarrow core is the 0.9.0 release through upstream's
bundler, the version zuarrow vendors, not the 0.8.0 `geoarrow-c` pins:
GCC 16 reports a null `snprintf()` destination in 0.8.0's
`ArrowSchemaToString()`, an `R CMD check` WARNING, which 0.9.0 rewrote.
`geoarrow-c` builds against it unchanged.
`tools/verify-vendor` re-derives the tree in
CI (`vendor.yaml`) and fails on any difference, as zuarrow's does.

`geoarrow-c`'s sources include `nanoarrow/nanoarrow.h`, so it cannot
link against zuarrow's hidden copy (zuarrow has no C table in 0.1.0).
zugeo compiles its own under a namespace (D2) and hides every symbol.
When zuarrow's C table lands (its §14), Q3 asks whether zugeo switches
to it. `kernel.c` includes `stdio.h`; Stage 0 checks with `nm` that no
`printf`, `abort` or `exit` symbol reaches the shared object, as the
zuclip and zucdt RFCs did for theirs. *2026-11-06 (Stage 0):* none
does once ryu is left out (above), and `tests/testthat/test-abi.R`
checks the export and import tables on every leg.

The R-tree, k-d tree and Hilbert function are zugeo's own C, written
from flatbush and kdbush (ISC) with credit in `inst/COPYRIGHTS`, and
tested against their published behaviour and serialised bytes (§9).

## 8. Errors

| Class | Raised when |
| --- | --- |
| `zugeo_error` | root of all below |
| `zugeo_layout_error` | storage violates GeoArrow (§6.3) |
| `zugeo_edges_error` | an edge type would be lost or a box would be wrong |
| `zugeo_crs_error` | combining columns with unequal CRS |
| `zugeo_metadata_error` | metadata or `geo` key is malformed |
| `zugeo_index_error` | raw index bytes fail validation |
| `zugeo_parquet_error` | `geo` key and native types disagree |

Each carries `column` where one applies, as zuarrow's conditions do.
`zuarrow_type_error` and `zuarrow_registry_error` pass through
unwrapped.

## 9. Testing

- **Corpus.** The `geoarrow-data` `v0.2.0` example files, every type and layout,
  in IPC and GeoParquet, pinned by hash in `tests/testthat/fixtures`.
  Files too large for the package go to a CI-only download, as zuarrow
  does. *Decided 2026-11-06 (Stage 1):* none is shipped, because
  `geoarrow-data` has no licence file or statement. The tests fetch the
  122 IPC files from the commit tagged `v0.2.0` (`e8eaa04`; the tag
  object itself is `1e90fc2`) when `ZUGEO_FETCH_FIXTURES=true`, as every
  CI workflow sets, or read them from `ZUGEO_CORPUS_DIR`, and check each
  against the md5 in `tests/testthat/corpus.txt`; otherwise they skip.
  Tests that run on CRAN build their schemas from specs instead. None of
  the example files carries a CRS (their metadata is `{}`), so CRS
  coverage is synthetic.
- **Oracles, CI only.** None is in `DESCRIPTION`. Their tests live in
  `tests/testthat/test-ci-*.R`, left out of the tarball by
  `.Rbuildignore`, and the `oracles` workflow runs them with
  `ZUGEO_ORACLES=true`, which turns a missing oracle into a failure, as
  zuarrow's design decided on 2026-11-04. `geoarrow` and `nanoarrow`
  (each `geo_vctr`
  equals a `geoarrow_vctr` of the same stream, both ways); `arrow` and
  pyarrow (extension metadata byte-identical after a round trip); DuckDB
  spatial (`ST_AsText` over zugeo's IPC and Parquet output equals
  zugeo's WKT); `sf` with GDAL (reads every GeoParquet file zugeo
  writes, CRS equal); `sf`, `geos`, `s2` and `wk` (each reads
  `geo_as_wkb()` output, and `geo_vctr()` reads theirs, value for
  value); DuckDB's `ST_AsHEXWKB` and `ST_Hilbert` (EWKB input and Q9);
  `gpq validate` (agrees with `geo_validate_parquet()` on the corpus).
- **Indexes.** flatbush and kdbush run under `node` in one CI leg and
  must return the same query results over the same bytes; `geo-index`
  in Python reads the bytes in another. The R-only legs compare
  against brute-force box scans on random data.
- **Exactness.** A property test round-trips every coordinate through
  WKT, WKB and both native layouts; a deliberate edge-type and
  CRS matrix proves each §6.3 error and each `lossy` downgrade.
- **Hostile input.** Truncated WKB, offsets past the end, a union with
  undeclared type ids, an index header lying about its size; none may
  crash under the sanitizer legs.

## 10. Performance targets

Measured in the benchmark stage on 10⁶ polygons of 10 vertices on the
Ubuntu release leg. Comparisons with `sf` and `geoarrow` run in a
CI-only benchmark script, like the oracles:

| Operation | Target |
| --- | --- |
| `arrow_to_r()` of a native column to `geo_vctr` | under 1 ms; no copy |
| `geo_box()` | at least 10 times faster than `sf::st_bbox()` per feature |
| `geo_sort()` | under 200 ms |
| `geo_rtree()` | under 300 ms |
| 10⁴ box queries | under 50 ms |
| `geo_as_wkb()` of a native column | under 100 ms |

Targets missed are recorded with the measurement, not hidden.

*Measured 2026-11-07 (Stage 8)* by `tools/benchmark.R` in `benchmark.yaml`
(ubuntu-latest, `rocker/r-ver:4.5.2`, x86-64), 10⁶ decagons, the median of
five runs. Two runs on two commits a few minutes apart differed by about
25% throughout, GitHub's runners being shared, so both are given:

| Operation | Target | Run 1 | Run 2 | |
| --- | --- | --- | --- | --- |
| `arrow_to_r()` to `geo_vctr` | under 1 ms; no copy | about 1 ms | 0.89 ms | met; no copy, but an O(n) check for nulls inside geometries |
| `geo_box()` | 10x `sf::st_bbox()` per feature | 129 ms, 123x | 161 ms, 125x | met |
| `geo_sort()` | under 200 ms | 183 ms | 233 ms | borderline |
| `geo_rtree()` | under 300 ms | 210 ms | 267 ms | met |
| 10⁴ box queries | under 50 ms | 15 ms | 19 ms | met |
| `geo_as_wkb()` | under 100 ms | 365 ms | 439 ms | **missed** |

`geo_sort()` met its target only after Stage 8 stopped `geo_hilbert()`
computing every box twice (699 to 400 ms on an Apple M-series laptop).
What remains of both it and `geo_box()` is D15's visitor, about 15 ns per
coordinate: `wk::wk_envelope()` over the same polygons as WKB takes 150 to
187 ms, so the visitor is on par with wk, and a bounds kernel specialised
to the native layouts is the way under 200 ms reliably. `geo_as_wkb()`
misses by its result, not its writer: building the WKB as one Arrow array
takes about a third of the time, and the rest is R allocating 10⁶ raw
vectors, which R alone does no faster. The list of raw vectors is the form
sf, geos and s2 take (Q2), so the target is not reachable in that form;
a WKB Arrow array (`geo_as_native()`'s counterpart for WKB) would meet it
and waits for a caller who wants it (§14).

## 11. Roadmap

The stages to v0.1.0, with their exit criteria and CI tiers, are in
[roadmap.md](roadmap.md). Stage numbers in this document are its.

## 12. Acceptance criteria for v0.1.0

- Every `geoarrow-data` file reads and writes exactly; every §6.3 error
  has a test that raises it.
- `geo_vctr` passes through `sf`, `geos` and `s2` and back by WKB in
  the CI-only oracles, with the CRS intact through `geo_crs_text()`.
- `DESCRIPTION` names no package outside the family.
- Index bytes agree with flatbush, kdbush and `geo-index`.
- No system library; `R CMD check --as-cran` clean on all r-actions
  legs with no network access; no forbidden symbol in the shared
  object.
- GeoParquet in the release, or moved to 0.2.0 by D12 with the reason
  in `NEWS.md`.

## 13. Decisions

All are **(C)**: this RFC decides them and the maintainer may overturn
any of them.

- **D1 (C).** A package of its own over `zuarrow`, not a zuarrow
  registration that delegates to `geoarrow`. Delegation would be fewer
  lines but makes `nanoarrow` a hard dependency of every geometry read,
  which zuarrow's design chose against on 2026-11-04.
- **D2 (C).** Vendor `geoarrow-c` with its own namespaced nanoarrow
  core rather than reimplement GeoArrow. It is the reference
  implementation, Apache-2.0, maintained by the specification's
  authors. The duplicate copy's size is measured in Stage 0.
  *Measured 2026-11-06 (Stage 0, macOS arm64):* the nanoarrow core
  compiles to a 174 KB object and the whole shared object is 232 KB
  after linking, against 714 KB for the nanoarrow package's.
- **D3.** No package outside the family in `Imports`, `LinkingTo` or
  `Suggests`, the family's rule (maintainer, 2026-11-05). Interchange
  is WKB and WKT (§6.6), and outside packages are CI-only oracles. The
  cost is one copy at the edge where `wk` would stream.
- **D4 (C).** `zujson` for all JSON. No JSON parser in `src/`.
- **D5 (C).** A `geo_vctr` holds positions over Arrow memory. Subsetting
  and sorting never copy buffers; materialisation happens only at
  export and at WKB or WKT conversion.
- **D6 (C).** CRS carried, never resolved. Equality is byte or JSON
  equality, documented as stricter than PROJ's.
- **D7 (C).** The `geo_` prefix. No CRAN package exports a `geo_`
  family that a family user would load beside zugeo, checked in
  Stage 0; `geos` uses `geos_` and `geoarrow` uses `geoarrow_`.
  *Checked 2026-11-06 (Stage 0):* nine CRAN packages export `geo_`
  names (`fuzzyjoin`, `stplanr`, `geojson`, `geoops`, `tigris`,
  `tidygeocoder`, `nominatimlite`, `CVXR`, `deeptime`), so the prefix is
  not free, but only one name in §5 is taken: `geo_nearest()`, by
  `geoops` 0.3.0. The rest of the prefix stands; D19 renames that
  one.
- **D8 (C).** Read `geoarrow.geometry` unions, never write them, until
  zuarrow writes unions. Mixed columns go out as WKB.
- **D9 (C).** No `mask_sf()`. Masking `sf` generics changes the meaning
  of code the user did not write, and WKB already gives `sf` a
  `geo_vctr`'s geometries without masking anything.
- **D10 (C).** GeoParquet 2.0 by default, 1.1 on request, covering
  column off by default. 2.0 is the specification's direction, and a
  covering column duplicates what native statistics already provide.
- **D11 (C).** No threads in v0.1.0. Box, Hilbert and pack are linear,
  memory-bound passes; threading them in an R package costs more in
  CRAN portability than it buys at 10⁶ rows. §14 revisits with
  measurements.
- **D12 (C).** GeoParquet does not hold the release. If `qio` 0.2.0 is
  not on CRAN when Stage 8 closes, Stage 7 moves to zugeo 0.2.0.
- **D13 (C).** Flatbush and kdbush byte formats for indexes, so the
  persisted index is readable outside R.
- **D14 (maintainer, 2026-11-05).** `geo_crs_equal()` gets three
  levels, `"identical"` by default, and answers `NA` when it cannot
  tell. It keeps D6: zugeo's own checks use `"identical"` only, and no
  level resolves a code to a definition.
- **D15 (maintainer, 2026-11-05).** One coordinate visitor in C under
  every kernel, instead of a loop per kernel and layout. It is
  internal; the public C table (§14) may expose it later.
- **D16 (maintainer, 2026-11-05).** `geo_extent` is the one box type:
  returned by `geo_box()`, taken by queries, reported by
  `geo_parquet_info()`.
- **D18 (maintainer, 2026-11-06).** WKT numbers go through `zufast`:
  a local patch to the vendored `geoarrow-c` replaces
  `GeoArrowPrintDouble()` with `zuf_format_f64()` (shortest round trip,
  positional or scientific, at most 25 characters) and
  `GeoArrowFromChars()` with `zuf_parse_f64()` (correctly rounded on
  every platform and rounding mode). A writer `precision` below the
  default stays a lossy opt-in. Libraries that print WKT exactly by
  default (DuckDB, the georust `wkt` crate, `orb`, `go-geom`,
  WellKnownGeometry.jl) all print shortest round-trip digits with no
  decimal cap; the ones that use a fixed digit budget (GEOS, JTS,
  PostGIS, GDAL, `wk`, `sf`) lose digits by default. Survey of
  2026-11-06, from their sources. Closes Q11.
- **D19 (maintainer, 2026-11-06).** `geo_nearest()` is
  `geo_query_nearest()`, because `geoops` 0.3.0 exports `geo_nearest()`
  and the new name matches `geo_query_box()` and `geo_query_radius()`.
  Closes Q10.
- **D20 (C, 2026-11-06, Stage 1).** zugeo reads GeoArrow schemas with
  its own C (`src/zgo_schema.c`), not `geoarrow-c`'s
  `GeoArrowSchemaViewInit()`. At `b3db89f` that function rejects
  `geoarrow.geometry` and `geoarrow.geometrycollection` as unrecognised
  names, accepts only `list` offsets, and matches `geoarrow.wkb` by
  prefix, so it cannot cover §2. The same gaps are expected in
  `geoarrow-c`'s array views, so Stages 2, 3 and 5 walk unions and
  `large_list` buffers in zugeo's own code (D15's visitor) and use
  `geoarrow-c` for what it supports. Two leniencies, both from
  `format.md` ("implementations must be able to ingest arrays with other
  names when the interpretation is unambiguous"): an explicit `"edges":
  "planar"` is read as planar, and a width-three interleaved child named
  `xym` is XYM.
- **D21 (C, 2026-11-06, Stage 2).** Native arrays are walked by zugeo's
  own C (`src/zgo_array.c`) over nanoarrow array views, which read every
  list width and unions, and the walk drives `geoarrow-c`'s
  `GeoArrowVisitor`, so its WKT and WKB writers consume it unchanged.
  This is the traversal half of D15, built in Stage 2 because `format()`
  needs it; Stage 5's kernels are reductions over the same walk.
  Gathering rows for export builds with nanoarrow, which builds a union
  only when its type ids are its child indices; zugeo builds against a
  copy of the schema whose unions are numbered `0..n-1` and rewrites the
  type id buffer to GeoArrow's ids after, which changes no value.
- **D22 (C, 2026-11-07, Stage 3).** `geoarrow-c`'s WKB reader at
  `b3db89f` reads past the end of a truncated buffer: after a coordinate
  sequence it advances its data pointer but not its remaining size, so
  every later bounds check counts bytes already read, and the size of
  the sequence is a `uint32_t` product that can wrap. Stage 3's
  truncation test returned garbage coordinates for WKB cut short by a
  few bytes. `tools/patches/0002` fixes both; the fuzz target covers the
  reader from now on. To be reported upstream.
- **D17 (maintainer, 2026-11-05).** `geo_parquet_info()` joins the
  GeoParquet functions and shares their gate (D12).
- **D23 (C, 2026-11-07, Stage 7).** GeoParquet over `qio` 0.1.2; a CRS
  zugeo cannot state as PROJJSON leaves the `geo` key out rather than be
  resolved; the key and the native type disagree only at the
  `"authority"` level. §6.9 has the details.

## 14. Later versions, in the order they are expected

- **A C table**: `inst/include/zugeo.h` and `R_GetCCallable("zugeo",
  "zugeo_api_v1")` with array views, box and index entry points, so
  `zuclip` and `zucdt` read coordinates without an R round trip.
- **GeoJSON through `zujson`**: `geo_read_geojson()` parsing straight
  into native buffers, and the reverse.
- **Geodesic measures** through GeographicLib's `geodesic.c` (MIT, one
  file, the code PROJ uses): length, area and distance on the
  ellipsoid, which gives the `karney` edge type a meaning beyond being
  carried, as DuckDB's `_Spheroid` functions and `orb`'s `geo` package
  do.
- **Exact planar kernels**: area, length, centroid, with `zuexact`
  (RFC 0023) summation so results do not depend on vertex order; the
  core of `geoarrow-rs`'s and `geoarrow-js`'s kernel sets.
- **Affine transforms**: translate, scale, rotate, over the buffers.
- **FlatGeobuf**: its index is §6.8's packed Hilbert R-tree, and the
  rest is FlatBuffers. Reading by HTTP range requests through `zuhttp`
  matches its main use.
- **Vector tiles through `zuproto`**: Mapbox Vector Tile encoding, with
  quadkeys, tile envelopes and web Mercator, which are a few dozen
  lines; DuckDB's `ST_AsMVT` and `orb`'s `encoding/mvt` and `maptile`
  are the references.
- **Grid cells as `zuh3`**, a separate package vendoring H3. Partitioned
  GeoParquet by cell, `geoparquet-io`'s feature, then belongs to `qio`
  or `zulake`, with zugeo supplying cell geometries.
- **Spherical bounds** for `spherical` edges, which removes §6.7's
  error for that edge type.
- **Memory-mapped indexes and GeoParquet** through zuarrow's mmap item
  and `zufs`.
- **Threads** for sort and pack, if §10's measurements ask for it.
- **Faster kernels** (§10, 2026-11-07): a bounds pass specialised to the
  native layouts beside D15's visitor, and WKB written to an Arrow array
  rather than a list of raw vectors.
- **`zuclip` on buffers**: polygon booleans, offsets, clipping to a
  box and simplification over `geo_vctr`, once `zuclip` exists.
- **Triangulation in `zucdt`**: `earcut.hpp` (ISC) belongs beside
  constrained Delaunay there rather than in zugeo.
- **Spatial weights from the indexes** (`libpysal`'s `Graph`):
  k nearest and distance-band graphs from the k-d tree, box contiguity
  from `geo_join_box()`, as a focal, neighbour, weight table with row
  standardisation and spatial lag.
- **More sort keys**: Morton order, geohash and quadbin beside
  `geo_hilbert()`, for partitioning as `dask-geopandas`'
  `spatial_shuffle()` does.
- **An STR loader** beside Hilbert, flagged in the index header since
  flatbush readers assume Hilbert, and nearest-neighbour search with a
  caller-supplied exact distance as a C hook for siblings
  (`geo-index`).
- **Point in polygon through `tg`** (MIT, one C file), in a separate
  package, to refine box-join candidates; it is the engine scope §1.1
  declines for zugeo.
- **Streaming to `wk` without a dependency**: a `wk_handle()` method
  registered from a load hook only when `wk` is already loaded, driving
  `wk`'s handlers through a vendored copy of its MIT-licensed `wk-v1.h`.
  It removes §6.6's copy and adds no `DESCRIPTION` entry, but it binds
  zugeo to `wk`'s C ABI, so it waits for the maintainer to want it.

## 15. Open questions

All eleven had an answer on 2026-11-06. Each line keeps the question and
records the answer, or where it is decided; the stage that verifies an
assumption is named.

- **Q1.** Will zuarrow let a registered extension handler receive a
  dense-union storage type? *Answered 2026-11-06: yes, by
  [pedrobtz/zuarrow#172](https://github.com/pedrobtz/zuarrow/pull/172)
  (closing #171), for `dense_union` and `sparse_union`, at any depth,
  sliced or not; an unregistered union still errors. Its
  `tools/make-union-fixture.py` makes the union test file Stage 2
  needs.*
- **Q2.** Should `geo_as_wkb()` mark its result with a class? *Decided
  2026-11-06: no, a plain list of raw vectors with the `crs`
  attribute; a borrowed class would couple zugeo to `wk`. Verified
  2026-11-07 (Stage 3): `sf::st_as_sfc()`, `geos::geos_read_wkb()` and
  `s2::s2_geog_from_wkb()` take it; `wk::new_wk_wkb()` wants the list
  without attributes.*
- **Q3.** Does zugeo drop its own nanoarrow copy when zuarrow publishes
  a C table? *Decided 2026-11-06: not in 0.x. The copy costs 174 KB
  (D2); linking through zuarrow would tie zugeo's releases to its ABI.
  Revisit when zuarrow's C table is stable and `geoarrow-c` can build
  against it.*
- **Q4.** Does `qio` interpret GeoParquet, or stay geometry-agnostic
  with zugeo owning the `geo` key? *Proposed 2026-11-06 in
  [pedrobtz/qio#21](https://github.com/pedrobtz/qio/issues/21): qio
  exposes the raw facts (native types with `crs` and algorithm, row-group
  bounds, footer pairs, row-group selection, and writing them), zugeo
  owns the `geo` key and CRS meaning. The decision is qio's.* *Answered
  2026-11-07: as proposed, in qio 0.1.2 ([pedrobtz/qio#22](https://github.com/pedrobtz/qio/pull/22));
  qio writes and reports the native types and statistics, zugeo the `geo`
  key (D23).*
- **Q5.** Does `sf::st_crs()` accept every string `geo_crs_text()`
  returns, PROJJSON included? *Verified 2026-11-07 (Stage 3):
  `sf::st_crs()` reads `OGC:CRS84`, `EPSG:4326`, `EPSG:3857` and a
  compact PROJJSON WGS 84 as `geo_crs_text()` writes them; the last
  equals `st_crs(4326)`, though PROJ finds no EPSG code in it.*
- **Q6.** Is v0.1.0 a CRAN submission? *Decided 2026-11-06: yes, after
  zuarrow is on CRAN, because `Remotes:` is refused there. #14 carries
  that as its first item.*
- **Q7.** A shared conformance suite with `geoarrowrs` and `geoarrow`?
  *Decided 2026-11-06: no new suite. `geoarrow-data` is the shared
  corpus; zugeo offers it the fixtures it makes (a union-encoded
  geometry file in Stage 2, the CRS and edges matrix in Stage 4, the
  WKT number edge cases in Stage 3) as pull requests.*
- **Q8.** Does `geoarrow-c`'s WKB reader keep EWKB's SRID? *Answered
  2026-11-06: it reads EWKB and discards the SRID; zugeo reads it
  first (§6.6). Reported upstream as geoarrow/geoarrow-c#191.
  Implemented 2026-11-07 (Stage 3) for the outer geometry, the one
  PostGIS and DuckDB write; an SRID on a nested geometry is still read
  past by `geoarrow-c` and dropped, which no producer zugeo knows of
  writes.*
- **Q9.** Do DuckDB's `ST_Hilbert`, `geopandas`' `hilbert_distance()`
  and flatbush use the same grid and curve orientation? *Answered
  2026-11-07 (Stage 5): flatbush and DuckDB agree exactly. On 401 boxes,
  `geo_hilbert()`, flatbush v4.7.0's own `hilbert()` with its `finish()`
  mapping (`tests/testthat/data/hilbert-flatbush.csv`, from
  `tools/make-hilbert-fixture.js`) and DuckDB spatial's `ST_Hilbert`
  over the same extent give identical keys; `test-kernel.R` and
  `test-ci-kernels.R` keep checking both. `geopandas` was not checked
  (no Python in CI).*
- **Q10.** `geo_nearest()` was also exported by `geoops`. *Decided
  2026-11-06: renamed `geo_query_nearest()` (D19).*
- **Q11.** `geoarrow-c`'s WKT writer prints at most 16 digits after the
  point, so small values lose digits and values below 1e-16 print as 0.
  *Decided 2026-11-06: print and parse through `zufast` (D18).
  Implemented 2026-11-07 (Stage 3) as `tools/patches/0001`; the
  property test of §6.3 passes on every corpus coordinate and on edge
  cases down to 5e-324. A number outside the double range (`1e400`) is
  now a parse error rather than an infinity, and a leading `+` is
  accepted as `strtod()` did, though not before another sign (`+-1`, #35,
  2026-11-08).*

Found while answering Q8, not yet reported upstream: `geoarrow-c`'s
metadata parser (`metadata.c`, `crs_type`) compares the key rather than
the value and omits `== 0`, so only the value's length picks the CRS
type: `"crs_type": "epsg"` reads as `srid`. zugeo is unaffected, because
it parses metadata with `zujson` (D4).

## 16. What this RFC does not decide

The print and `format()` widths, the `geo_box()` column names beyond
the specification's `xmin`..`ymax`, `node_size` defaults beyond the
ones flatbush uses, the row-group size `geo_write_parquet()` aims at,
the article's examples, and any `qio` function names, which belong to
qio's design.

## 17. Sources and verification

Checked on 4 November 2026:

- crandb: `zugeo`, `geoarrowrs` and `geoparquet` `not_found`; `geoarrow`
  0.4.4 (2026-09-16, `Imports: nanoarrow (>= 0.5.0), wk (>= 0.9.0)`),
  `wk` 0.9.5, `geos` 0.2.5, `s2` 1.1.13 (`SystemRequirements: cmake,
  OpenSSL >= 1.0.1, Abseil >= 20230802.0`), `sf` 1.1-3, `sfarrow` 0.4.1,
  `libgeos` 3.11.1-3, `BH` 1.90.0-1.
- `gh repo view pedrobtz/zugeo`: no such repository.
- `geoarrow/geoarrow` at `v0.2.0` (`005d02d`): `extension-types.md`
  ("Format version 0.2", the eleven names, `crs`, `crs_type`, `edges`)
  and `format.md` (layouts, dense union type ids, box, nulls, empties,
  list types).
- `geoarrow/geoarrow-c` at `b3db89f` (2026-10-21): `src/geoarrow` file
  list and sizes, the `nanoarrow/nanoarrow.h` includes, kernel names
  `format_wkt`, `as_geoarrow`, `box`, `box_agg`,
  `unique_geometry_types_agg`; CMake version `0.2.0-SNAPSHOT`.
- `opengeospatial/geoparquet` `v2.0.0-rc.1` release notes (native types,
  removal of covering columns and native GeoArrow encodings, CRS rules).
- `JosiahParry/geoarrowrs` README.
- `mourner/flatbush` `v4.7.0` (`index.js`: magic `0xfb`, `VERSION = 3`,
  Hilbert sort), `mourner/kdbush` `v4.1.0`, both ISC;
  `kylebarron/geo-index` README.
- `pedrobtz/zuarrow` `.agents/design.md` §3, §6.2, §6.6, §6.10, §14.

- `pedrobtz/qio` `.agents/TYPES.md`, `carquet.md`, `plan.md`;
  `NAMESPACE`; crandb `qio` 0.1.1 (2026-09-29).
- `pedrobtz/zujson` `NAMESPACE`.

Checked on 5 November 2026, for §1.5: the READMEs and repository
metadata of `geoarrow/geoarrow-python`, `geoarrow/geoarrow-rs` (its
`rust/` crates and `geoarrow-expr-geo` sources), `geoarrow/geoarrow-js`,
`shapely/shapely`, `geopandas/geopandas` (`io/arrow.py`, `base.py`),
`geoparquet/geoparquet-io`, `planetlabs/gpq`, `paulmach/orb`,
`twpayne/go-geom`, `peterstace/simplefeatures`, `tidwall/rtree`,
`georust/geo`, `georust/rstar`, `georust/wkb`, `apache/sedona-db`,
`duckdb/duckdb-spatial` (`docs/functions.md`), `flatgeobuf/flatgeobuf`
(`src/cpp/packedrtree.cpp`), `uber/h3` (`v4.5.0`, 2026-05-21),
`geographiclib/geographiclib-c` (`src/geodesic.c`, 73 216 bytes),
`mapbox/earcut.hpp`. Licences are GitHub's SPDX field.

Checked on 5 November 2026, for §1.6: GeometryOps.jl documentation
(paradigms, manifolds, `SpatialTreeInterface`), `JuliaGeo/GeoInterface.jl`,
`GeoFormatTypes.jl`, `rafaqz/Extents.jl`, `SortTileRecursiveTree.jl`,
`JuliaGeo/GeoArrow.jl`, `GeoParquet.jl`, `CoordRefSystems.jl`;
`pyproj` `CRS` API, `georust/geozero`, `kylebarron/geo-index`,
`tidwall/tg` (README, `POLYGON_INDEXING.md`), `libpysal` `Graph`,
`CartoDB/quadbin-py`, `holoviz/spatialpandas`, `Oreilles/polars-st`.
From memory rather than fetched: `pyogrio`'s `read_info()` fields,
`dask-geopandas`, and the licences of `libpysal` and `quadbin`.

Not verified: that `sf::st_crs()` reads PROJJSON text (Q5); that
`sf`, `geos` and `s2` take a plain list of raw WKB (Q2); DuckDB's and Spark's
GeoArrow export options (§3), which Stage 2's oracle tests settle; the
size of `geoarrow-c`'s compiled object and its symbol imports (Stage 0;
measured 2026-11-06, see D2 and §7).
