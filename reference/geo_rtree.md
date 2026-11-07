# Packed spatial indexes

`geo_rtree()` packs each geometry's box into a static R-tree, and
`geo_kdtree()` packs points into a static k-d tree (design section 6.8).
Both are immutable, bulk-loaded and held as one raw vector in flatbush's
and kdbush's serialised formats, so `geo_index_raw()` gives bytes that
flatbush and kdbush in JavaScript and geo-index in Rust and Python load
unchanged, and `geo_index_from_raw()` reads such bytes back, checking
them first.

## Usage

``` r
geo_rtree(x, node_size = 16L, lossy = c("error", "warn", "allow"))

geo_kdtree(x, node_size = 64L)

geo_index_raw(index)

geo_index_from_raw(raw)
```

## Arguments

- x:

  A `geo_vctr` or a `geo_extent` for `geo_rtree()`; a `geo_vctr` of
  points for `geo_kdtree()`.

- node_size:

  Entries per node, 2 to 65535: flatbush's default of 16 for R-trees and
  kdbush's 64 for k-d trees.

- lossy:

  As for
  [`geo_box()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md).

- index:

  A `zugeo_index`.

- raw:

  A raw vector holding a flatbush or kdbush index.

## Value

`geo_rtree()`, `geo_kdtree()` and `geo_index_from_raw()`: a
`zugeo_index`. `geo_index_raw()`: a raw vector.

## Details

Null and empty geometries are left out of an index, and queries return
positions in the vector the index was built from. An index read from raw
bytes numbers its items 1 to n in the order they were added.

## See also

[`geo_query_box()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md)
for queries and joins.

## Examples

``` r
x <- geo_points(c(0, 5, 9), c(0, 5, 9))
tree <- geo_rtree(x)
geo_query_box(tree, geo_extent(4, 4, 10, 10))
#> [1] 2 3
bytes <- geo_index_raw(tree)
geo_query_box(geo_index_from_raw(bytes), geo_extent(4, 4, 10, 10))
#> [1] 2 3
```
