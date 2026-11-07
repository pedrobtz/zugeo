# Geometry vectors over Arrow memory

A `geo_vctr` is a vector of geometries that stay in the Arrow arrays
they came in (design section 6.1). It is an integer vector of row
positions into those arrays, so subsetting, reversing and sorting never
copy a buffer; rows are gathered only when the vector is written back to
Arrow. Reading a GeoArrow column with zuarrow gives one, once zugeo is
loaded, and writing one gives the column back with its extension
metadata unchanged.

## Usage

``` r
geo_vctr(x)

is_geo_vctr(x)
```

## Arguments

- x:

  An Arrow array handle of a GeoArrow field, from zuarrow or nanoarrow,
  or a `geo_vctr`.

## Value

A `geo_vctr`.

## Examples

``` r
is_geo_vctr(1)
#> [1] FALSE
```
