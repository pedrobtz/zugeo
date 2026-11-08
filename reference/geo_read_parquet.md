# Read and write GeoParquet

`geo_read_parquet()` reads a GeoParquet file into a data frame whose
geometry columns are `geo_vctr`s, and `geo_write_parquet()` writes one
(design section 6.9). Both need the qio package. Other columns go
through qio's own mapping.

## Usage

``` r
geo_read_parquet(
  path,
  bbox = NULL,
  columns = NULL,
  lossy = c("error", "warn", "allow")
)

geo_write_parquet(
  x,
  path,
  sort = c("hilbert", "none"),
  version = c("2.0", "1.1"),
  row_group_size = 100000L,
  compression = c("zstd", "snappy", "gzip", "lz4", "uncompressed")
)
```

## Arguments

- path:

  A Parquet file path.

- bbox:

  `NULL`, a `geo_extent` of length one, or `c(xmin, ymin, xmax, ymax)`,
  applied to the primary geometry column.

- columns:

  `NULL` for every column qio reads, or a character vector of column
  names.

- lossy:

  For `bbox` over non-planar edges: `"error"`, `"warn"` or `"allow"` the
  planar row filter.

- x:

  A data frame with at least one `geo_vctr` column, or a `geo_vctr`,
  written as the column `geometry`.

- sort:

  `"hilbert"` to order the rows by
  [`geo_hilbert()`](https://pedrobtz.github.io/zugeo/reference/geo_hilbert.md)
  of the first geometry column, or `"none"`.

- version:

  `"2.0"` or `"1.1"`.

- row_group_size:

  Rows per row group; the GeoParquet distribution guide suggests 50,000
  to 200,000.

- compression:

  As for
  [`qio::write_parquet()`](https://pedrobtz.github.io/qio/reference/write_parquet.html);
  the guide suggests zstd.

## Value

`geo_read_parquet()`: a data frame. `geo_write_parquet()`: `path`,
invisibly.

## Details

A geometry column is one the `geo` footer key lists or one stored in
Parquet's native `GEOMETRY` or `GEOGRAPHY` type; when a file has both,
they must agree on the CRS and the edges, or the read is a
`zugeo_parquet_error`. A missing CRS in either is OGC:CRS84, as both
specifications say, and the CRS `srid:0` or `null` is none. Two
statements of a CRS disagree when their authority codes differ or their
PROJJSON differs structurally; one that zugeo cannot compare without
PROJ is taken on trust, and the geo key's PROJJSON is kept.

`bbox` skips the row groups whose box, from the native statistics or
else a `covering` column's, misses it, and then keeps the rows whose
geometry's box intersects it. That row filter is planar, so on lines and
polygons with non-planar edges, which can bulge past their vertices'
box, it is a `zugeo_edges_error` unless `lossy` says otherwise, as for
[`geo_box()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md).
GeoParquet 1.1's native GeoArrow encodings are nested Parquet columns,
which qio does not read yet; such a column is a `zugeo_parquet_error`.

`geo_write_parquet()` writes GeoParquet 2.0 by default: WKB in the
native `GEOMETRY` type, or `GEOGRAPHY` with its algorithm for non-planar
edges, the `geo` key beside it, rows in Hilbert order of the first
geometry column, and row groups of `row_group_size` rows. The `geo` key
needs every CRS as PROJJSON, OGC:CRS84 or none, because zugeo never
resolves a code to its definition; a CRS given as a code or WKT is then
written in the Parquet type only, and the `geo` key is left out, as the
specification advises for writers that cannot produce PROJJSON. A
PROJJSON CRS too long for the Parquet type's 127 bytes is stored under
the footer key `projjson_crs_<column>`. `version = "1.1"` writes plain
binary with the `geo` key alone, which then must hold the CRS, so a code
is a `zugeo_crs_error` there. The `geo` key's `bbox` is written for
planar edges only.

## See also

[`geo_parquet_info()`](https://pedrobtz.github.io/zugeo/reference/geo_parquet_info.md)
for the metadata alone,
[`geo_validate_parquet()`](https://pedrobtz.github.io/zugeo/reference/geo_validate_parquet.md).

## Examples

``` r
path <- tempfile(fileext = ".parquet")
df <- data.frame(id = 1:3)
df$geometry <- geo_points(c(0, 5, 9), c(0, 5, 9), crs = "OGC:CRS84")
geo_write_parquet(df, path)
geo_read_parquet(path, bbox = c(4, 4, 10, 10))
#>   id    geometry
#> 1  2 POINT (5 5)
#> 2  3 POINT (9 9)
```
