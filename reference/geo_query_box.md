# Query packed indexes

`geo_query_box()` finds the indexed geometries whose boxes intersect
each query box. `geo_query_radius()` finds the points of a k-d tree
within a distance. `geo_query_nearest()` finds up to `k` geometries of
an R-tree by box distance, nearest first; a box distance can be smaller
than the distance between the geometries, so these are candidates that
GEOS or S2 can refine. `geo_join_box()` pairs every box of `y` with the
indexed boxes it intersects, in one call; when `y` is itself an R-tree
both trees are descended together (design section 6.8).

## Usage

``` r
geo_query_box(index, extent)

geo_query_radius(index, x, y, r)

geo_query_nearest(index, x, y, k = 1L, max_distance = Inf)

geo_join_box(index, y, lossy = c("error", "warn", "allow"))
```

## Arguments

- index:

  A `zugeo_index`.

- extent:

  A `geo_extent`.

- x, y:

  Query coordinates for `geo_query_radius()` and `geo_query_nearest()`.

- r:

  The radius.

- k:

  The most neighbours to return.

- max_distance:

  The largest box distance to return.

- lossy:

  As for
  [`geo_box()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md).

## Value

For `geo_query_box()` and `geo_query_radius()`, an integer vector or a
data frame of `query` and `row`. For `geo_query_nearest()`, a data frame
of `query`, `row` and `distance`. For `geo_join_box()`, a data frame of
`x` (positions in the indexed vector) and `y`.

## Details

A query of one box or point gives the matching positions as a sorted
integer vector; several give a data frame of `query` and `row`.

## Examples

``` r
x <- geo_points(c(0, 5, 9), c(0, 5, 9))
tree <- geo_rtree(x)
geo_query_nearest(tree, 4, 4, k = 2)
#>   query row distance
#> 1     1   2 1.414214
#> 2     1   1 5.656854
geo_join_box(tree, geo_extent(c(-1, 8), c(-1, 8), c(1, 10), c(1, 10)))
#>   x y
#> 1 1 1
#> 2 3 2
```
