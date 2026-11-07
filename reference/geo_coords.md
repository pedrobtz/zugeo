# Coordinates as columns

`geo_coords()` gives one row per vertex, with the CRS and edge type as
the attributes `crs` and `edges`, which `geo_from_coords()` takes back:
`x`, `y`, and `z` and `m` when present, with `feature` (the element of
`x`), `part` (the simple geometry within a multi-geometry or collection)
and `ring` (the polygon ring, `NA` outside polygons). Null and empty
geometries have no rows. `geo_from_coords()` is the reverse for one
native type, and `geo_points()` makes points straight from vectors
(design section 6.10).

## Usage

``` r
geo_coords(x)

geo_from_coords(
  coords,
  type,
  n = NULL,
  crs = NULL,
  edges = NULL,
  layout = c("separated", "interleaved")
)

geo_points(
  x,
  y,
  z = NULL,
  m = NULL,
  crs = NULL,
  edges = NULL,
  layout = c("separated", "interleaved")
)
```

## Arguments

- x:

  A `geo_vctr` for `geo_coords()`; x coordinates for `geo_points()`.

- coords:

  A data frame with `x`, `y`, optionally `z` and `m`, and `feature`,
  `part` and `ring` as `geo_coords()` gives them, ordered by `feature`.
  `part` and `ring` default to 1.

- type:

  One of `"point"`, `"linestring"`, `"polygon"`, `"multipoint"`,
  `"multilinestring"` and `"multipolygon"`.

- n:

  The number of features; by default the largest `feature`. Features
  with no rows are empty.

- crs, edges:

  As for
  [`geo_vctr()`](https://pedrobtz.github.io/zugeo/reference/geo_vctr.md);
  by default the `crs` and `edges` attributes of `coords`.

- layout:

  As for
  [`geo_as_native()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md).

- y, z, m:

  Coordinate vectors; `z` and `m` may be `NULL`.

## Value

`geo_coords()`: a data frame; the others: a `geo_vctr`.

## Examples

``` r
x <- geo_vctr("POLYGON ((0 0, 1 0, 0 1, 0 0))")
geo_coords(x)
#>   x y feature part ring
#> 1 0 0       1    1    1
#> 2 1 0       1    1    1
#> 3 0 1       1    1    1
#> 4 0 0       1    1    1
geo_points(1:3, 4:6)
#> <geo_vctr[3] geoarrow.point native, xy, separated; crs none; edges planar>
#> [1] POINT (1 4)
#> [2] POINT (2 5)
#> [3] POINT (3 6)
```
