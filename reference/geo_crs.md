# Coordinate reference systems, carried exactly

`geo_crs()` returns the CRS of a GeoArrow field, or makes one from a
string. zugeo stores a CRS exactly as given, tagged with its GeoArrow
`crs_type`, and never resolves or transforms it (design section 6.4).

## Usage

``` r
geo_crs(x, crs_type = NULL)
```

## Arguments

- x:

  A string, `NULL` or `NA` (no CRS), a `zugeo_crs`, a `zugeo_type` from
  [`geo_type_of()`](https://pedrobtz.github.io/zugeo/reference/geo_type_of.md),
  or an Arrow schema, array or stream handle with one GeoArrow field.

- crs_type:

  `NULL` to classify a string, or one of `"projjson"`, `"wkt2:2019"`,
  `"authority_code"` and `"srid"`.

## Value

A `zugeo_crs`: a list of `value` (`NULL`, a string, or the parsed
PROJJSON object) and `type` (a `crs_type`, or `NA`).

## Details

A string is classified as GeoArrow asks: a JSON object is PROJJSON, a
string starting with a WKT2 keyword is `"wkt2:2019"`, one of the form
`AUTHORITY:CODE` is `"authority_code"`, and anything else has no
`crs_type`. `crs_type` overrides the classification.

## See also

[`geo_crs_equal()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_equal.md)

## Examples

``` r
geo_crs("OGC:CRS84")
#> <zugeo_crs authority_code: OGC:CRS84>
geo_crs(NULL)
#> <zugeo_crs: none>
```
