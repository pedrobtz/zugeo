
<!-- README.md is generated from README.Rmd. Please edit that file -->

# zugeo

<!-- badges: start -->

[![R-CMD-check](https://github.com/pedrobtz/zugeo/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zugeo/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zugeo/gh-pages/badges/coverage.svg)](https://github.com/pedrobtz/zugeo/actions/workflows/coverage.yaml)
[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

DuckDB, GDAL and the Python geospatial stack hand geometries around as
[GeoArrow](https://geoarrow.org/) columns and store them as
[GeoParquet](https://geoparquet.org/). In R they usually become `sf`
objects on the way in: one R object per geometry, a coordinate reference
system resolved through PROJ, and digits that depend on who printed the
text.

zugeo keeps a geometry column as what it is, Arrow memory with its CRS
and edge type, and works on it there.

- **Geometries stay in Arrow memory.** A `geo_vctr` holds positions into
  the arrays it was read in, so subsetting and sorting copy no
  coordinates. With zugeo loaded,
  [zuarrow](https://github.com/pedrobtz/zuarrow) reads and writes every
  GeoArrow type as one.
- **Exact or an error.** WKB, WKT and the native layouts convert with
  every coordinate intact: WKT prints the shortest digits that read back
  to the same double. A conversion that would lose an edge type is an
  error unless you ask for it.
- **A CRS is carried, never guessed.** zugeo stores a CRS as it was
  given and compares it without PROJ; it never resolves a code to a
  definition.
- **Kernels over the buffers.** Bounding boxes, Hilbert keys and spatial
  sorting run over the coordinates without an R object per geometry, and
  the packed R-tree and k-d tree indexes are byte for byte those of
  [flatbush](https://github.com/mourner/flatbush) and
  [kdbush](https://github.com/mourner/kdbush).
- **GeoParquet 2.0 and 1.1**, with the
  [qio](https://github.com/pedrobtz/qio) package: native `GEOMETRY`
  types, row groups skipped by box, and a validator that reports what
  `gpq validate` does.

zugeo has no system requirements: it bundles
[geoarrow-c](https://github.com/geoarrow/geoarrow-c), and imports only
zuarrow and zujson.

## Installation

Install the released version from CRAN:

``` r
install.packages("zugeo")
```

Or the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("pedrobtz/zugeo")
```

## Usage

``` r
library(zugeo)
```

A `geo_vctr` reads WKT or WKB and keeps the CRS beside the geometries.

``` r
cities <- geo_vctr(
  c("POINT (-9.139 38.722)", "POINT (-8.611 41.150)", "POINT (2.352 48.857)"),
  crs = "OGC:CRS84"
)
cities
#> <geo_vctr[3] geoarrow.wkt wkt; crs authority_code; edges planar>
#> [1] POINT (-9.139 38.722)
#> [2] POINT (-8.611 41.150)
#> [3] POINT (2.352 48.857)
```

Coordinates come back exactly as they went in, through any encoding.

``` r
x <- geo_points(0.1 + 0.2, 1 / 3)
cat(geo_as_wkt(x))
#> POINT (0.30000000000000004 0.3333333333333333)
identical(geo_coords(geo_vctr(geo_as_wkb(x)))$x, 0.1 + 0.2)
#> [1] TRUE
```

An R-tree finds what intersects a box. Its bytes are in flatbush’s
format, magic byte `fb` first, so flatbush in JavaScript and geo-index
in Python load them unchanged.

``` r
tree <- geo_rtree(cities)
geo_query_box(tree, geo_extent(-10, 38, -8, 42, crs = "OGC:CRS84"))
#> [1] 1 2
geo_index_raw(tree)[1:2]
#> [1] fb 38
```

Lines on the sphere have no planar box, so asking for one is an error.

``` r
route <- geo_vctr("LINESTRING (-9.139 38.722, 2.352 48.857)",
  crs = "OGC:CRS84", edges = "spherical"
)
geo_box(route)
#> Error in `geo_box()`:
#> ! A planar box can be wrong for "spherical" edges, which may bulge past their vertices or cross the antimeridian. Pass `lossy = "warn"` or `"allow"` for the planar box anyway.
```

With qio installed, a data frame of geometries becomes GeoParquet.
Reading with `bbox` skips the row groups whose statistics miss the box,
then keeps the rows that meet it.

``` r
path <- tempfile(fileext = ".parquet")
df <- data.frame(name = c("Lisbon", "Porto", "Paris"))
df$geometry <- cities
geo_write_parquet(df, path)
geo_read_parquet(path, bbox = c(-10, 38, -8, 42))
#>     name              geometry
#> 1 Lisbon POINT (-9.139 38.722)
#> 2  Porto  POINT (-8.611 41.15)
```

Every function is prefixed `geo_`, apart from `zugeo_info()`. zugeo’s
errors inherit from `zugeo_error`, with a class for each kind, such as
`zugeo_edges_error` and `zugeo_crs_error`.

## Learn more

- [Geometry columns from DuckDB to
  sf](https://pedrobtz.github.io/zugeo/articles/duckdb-to-sf.html)
  follows one column from a DuckDB query through zugeo to sf and back.
- The [reference](https://pedrobtz.github.io/zugeo/reference/) lists
  every function by task.

## Related work

zugeo implements the [GeoArrow 0.2](https://geoarrow.org/format.html)
and [GeoParquet](https://geoparquet.org/) specifications over the
bundled geoarrow-c and nanoarrow libraries. It is tested on the
[geoarrow-data](https://github.com/geoarrow/geoarrow-data) corpus and,
in CI, against DuckDB, GDAL, sf, geos, s2, wk, gpq, flatbush, kdbush and
geo-index, and loads beside the geoarrow and nanoarrow packages.
