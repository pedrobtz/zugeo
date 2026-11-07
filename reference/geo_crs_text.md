# The CRS as one string for other packages

PROJJSON as compact JSON, any other CRS exactly as stored, `NA` for
none. PROJ reads all of these as user input, so
`sf::st_crs(geo_crs_text(x))` takes them (design section 6.4).

## Usage

``` r
geo_crs_text(x)
```

## Arguments

- x:

  Anything
  [`geo_crs()`](https://pedrobtz.github.io/zugeo/reference/geo_crs.md)
  takes.

## Value

A string.

## Examples

``` r
geo_crs_text(geo_vctr("POINT (1 2)", crs = "OGC:CRS84"))
#> [1] "OGC:CRS84"
```
