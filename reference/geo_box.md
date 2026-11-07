# Bounds, types and counts over the buffers

`geo_box()` gives each geometry's bounding box and `geo_box_all()` the
one box around them all, both as a
[`geo_extent()`](https://pedrobtz.github.io/zugeo/reference/geo_extent.md),
computed over the coordinate buffers with no R object per geometry
(design section 6.7). Z and M ranges come when the geometries have them.
A null geometry's box is `NA` and an empty one's `NaN`.

## Usage

``` r
geo_box(x, lossy = c("error", "warn", "allow"))

geo_box_all(x, lossy = c("error", "warn", "allow"))

geo_types(x)

geo_dims(x)

geo_n_coords(x)
```

## Arguments

- x:

  A `geo_vctr`.

- lossy:

  As for
  [`geo_as_wkb()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md):
  `"error"`, `"warn"` or `"allow"` a planar box for non-planar edges.

## Value

`geo_box()` and `geo_box_all()`: a `geo_extent`. `geo_types()`,
`geo_dims()`: character vectors. `geo_n_coords()`: an integer vector.

## Details

Bounds are planar. For a non-planar edge type a planar box can miss an
edge that bulges past its vertices or crosses the antimeridian, so on
geometries with edges `geo_box()` is a `zugeo_edges_error` unless
`lossy` says otherwise.

`geo_types()`, `geo_dims()` and `geo_n_coords()` give each geometry's
type, dimensions and number of coordinates (`NA` for a null).

## Examples

``` r
x <- geo_vctr(c("POINT (1 2)", "LINESTRING Z (0 0 1, 3 4 5)", NA))
geo_box(x)
#> <geo_extent[3]; crs none; edges planar>
#> [1] [1 2 NaN, 1 2 NaN]
#> [2] [0 0 1, 3 4 5]
#> [3] <null>
geo_box_all(x)
#> <geo_extent[1]; crs none; edges planar>
#> [1] [0 0 1, 3 4 5]
geo_types(x)
#> [1] "point"      "linestring" NA          
geo_n_coords(x)
#> [1]  1  2 NA
```
