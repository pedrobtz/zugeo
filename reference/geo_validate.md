# Report what is wrong with geometries, without repairing it

One row per finding (design section 6.11), what `gpq validate` checks
for geometry values: a ring that does not close (`unclosed_ring`), a
ring of fewer than four positions (`short_ring`), a linestring of one
position (`short_linestring`), a coordinate that is not finite in a
geometry other than an empty point (`non_finite`), parts of different
dimensions in one geometry (`mixed_dimensions`), and rings against the
RFC 7946 winding convention, exteriors counterclockwise
(`exterior_clockwise`, `interior_counterclockwise`), which Simple
Features does not require and are reported for information.

## Usage

``` r
geo_validate(x)
```

## Arguments

- x:

  A `geo_vctr`.

## Value

A data frame of `row` (the element of `x`), `issue`, `part` and `ring`
(`NA` outside a ring); no rows when nothing is wrong.

## Examples

``` r
geo_validate(geo_vctr(c("POLYGON ((0 0, 1 0, 0 1))", "POINT (1 2)")))
#>   row         issue part ring
#> 1   1 unclosed_ring    1    1
#> 2   1    short_ring    1    1
```
