# Extents: boxes as a vector

A `geo_extent` is the one box type zugeo uses (design D16): what
[`geo_box()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md)
returns, what index queries take. Each element is `xmin`, `ymin`,
`xmax`, `ymax`, with `zmin`, `zmax`, `mmin`, `mmax` when given, and the
vector carries the CRS and edge type of its geometries. An empty
geometry's box is all `NaN` and a null's is `NA`; both are disjoint from
everything.

## Usage

``` r
geo_extent(
  xmin,
  ymin,
  xmax,
  ymax,
  zmin = NULL,
  zmax = NULL,
  mmin = NULL,
  mmax = NULL,
  crs = NULL,
  edges = NULL
)

geo_extent_union(e)

geo_extent_intersection(e, f)

geo_extent_intersects(e, f)
```

## Arguments

- xmin, ymin, xmax, ymax, zmin, zmax, mmin, mmax:

  Numeric bounds, recycled. `zmin` and `zmax` come together, as do
  `mmin` and `mmax`.

- crs, edges:

  As for
  [`geo_vctr()`](https://pedrobtz.github.io/zugeo/reference/geo_vctr.md).

- e, f:

  `geo_extent` vectors.

## Value

`geo_extent()`, `geo_extent_union()` and `geo_extent_intersection()`: a
`geo_extent`. `geo_extent_intersects()`: a logical vector.

## Details

`geo_extent_union()` reduces to the one box covering every element;
`geo_extent_intersection()` and `geo_extent_intersects()` work pairwise,
recycling. A box with `xmin > xmax`, which GeoArrow uses for boxes that
cross the antimeridian, is a `zugeo_edges_error` in all three rather
than read as planar.

## Examples

``` r
e <- geo_extent(c(0, 5), c(0, 5), c(2, 6), c(2, 6))
geo_extent_union(e)
#> <geo_extent[1]; crs none; edges planar>
#> [1] [0 0, 6 6]
geo_extent_intersects(e, geo_extent(1, 1, 1.5, 1.5))
#> [1]  TRUE FALSE
```
