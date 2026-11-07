# GeoParquet metadata without reading rows

Reads a GeoParquet file's footer and nothing else, as `pyogrio`'s
`read_info()` does (design section 6.9, D17): its row count, its row
groups, and for each geometry column the encoding, Parquet type,
geometry types, CRS, edges, the file's box and each row group's box from
the native statistics, or else the `covering` column's. It shows what
`bbox` in
[`geo_read_parquet()`](https://pedrobtz.github.io/zugeo/reference/geo_read_parquet.md)
would skip. Needs the qio package.

## Usage

``` r
geo_parquet_info(path)
```

## Arguments

- path:

  A Parquet file path.

## Value

A `zugeo_parquet_info`: a list of `rows`, `version` (the `geo` key's,
`NA` without one), `primary_column`, `row_groups` (a data frame of
`row_group` and `rows`) and `columns`, one list per geometry column of
`encoding`, `logical_type` (`GEOMETRY`, `GEOGRAPHY`, or `NA` for plain
binary), `geometry_types` (`NULL` when unknown), `crs`, `edges`, `bbox`
(a `geo_extent` of one, from the `geo` key or else the union of the row
groups) and `row_group_bbox` (a `geo_extent` per row group).

## Examples

``` r
path <- tempfile(fileext = ".parquet")
geo_write_parquet(geo_points(1:4, 1:4), path, row_group_size = 2)
geo_parquet_info(path)
#> <zugeo_parquet_info: 4 rows in 2 row groups; GeoParquet 2.0.0>
#> * geometry: WKB GEOMETRY; Point; crs none; edges planar; bbox [1 1, 4 4]
```
