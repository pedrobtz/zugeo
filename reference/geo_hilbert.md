# Hilbert keys and spatial sorting

`geo_hilbert()` maps each geometry's box centre onto a 2^16 by 2^16 grid
over `extent` and gives its index along the Hilbert curve, with
flatbush's arithmetic exactly, so a zugeo sort and a flatbush index
agree (design section 6.7). Null and empty geometries have `NA`.
`geo_sort()` gives the permutation that orders `x` by key, nulls and
empties last, ties in their original order: `x[geo_sort(x)]` is the
sorted vector.

## Usage

``` r
geo_hilbert(x, extent = NULL, lossy = c("error", "warn", "allow"))

geo_sort(x, by = "hilbert", lossy = c("error", "warn", "allow"))
```

## Arguments

- x:

  A `geo_vctr`.

- extent:

  `NULL` for the box around `x`, or a `geo_extent` of length one.
  Centres outside it are clamped onto its edge.

- lossy:

  As for
  [`geo_box()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md).

- by:

  The sort key; `"hilbert"` is the one there is.

## Value

`geo_hilbert()`: a double vector of unsigned 32-bit keys. `geo_sort()`:
an integer permutation.

## Examples

``` r
x <- geo_points(c(5, 1, 3), c(5, 1, 3))
geo_hilbert(x)
#> [1] 2863311530          0  715827882
geo_sort(x)
#> [1] 2 3 1
```
