# Compare two coordinate reference systems without PROJ

Three levels, each looser than the last, after `pyproj`'s
`is_exact_same()` and `equals()` (design section 6.4, D14):

## Usage

``` r
geo_crs_equal(x, y, level = c("identical", "structural", "authority"))
```

## Arguments

- x, y:

  Anything
  [`geo_crs()`](https://pedrobtz.github.io/zugeo/reference/geo_crs.md)
  takes.

- level:

  One of `"identical"`, `"structural"` and `"authority"`.

## Value

`TRUE`, `FALSE` or `NA`.

## Details

- `"identical"`: both absent, the same string byte for byte, or the same
  PROJJSON object ignoring key order. zugeo's own checks use this level.

- `"structural"`: PROJJSON compared after dropping members that do not
  change coordinates (`$schema`, `name`, `remarks`, `usages`, `scope`,
  `area`, `bbox`) and treating integers and doubles alike. A string CRS
  that is not identical gives `NA`.

- `"authority"`: the same authority and code, from an `AUTHORITY:CODE`
  string or a PROJJSON `id`, with the authority's case ignored and the
  pairs that differ only in axis order (`OGC:CRS84` and `EPSG:4326`)
  treated as one. A side with no authority and code gives `NA`.

`NA` means zugeo cannot tell without PROJ, never that the two differ.

## Examples

``` r
geo_crs_equal("EPSG:4326", "EPSG:4326")
#> [1] TRUE
geo_crs_equal("OGC:CRS84", "EPSG:4326")
#> [1] FALSE
geo_crs_equal("OGC:CRS84", "EPSG:4326", level = "authority")
#> [1] TRUE
```
