# Make geometry vectors from WKB, WKT or Arrow

`geo_vctr()` reads well-known binary (a list of raw vectors, such as
[`sf::st_as_binary()`](https://r-spatial.github.io/sf/reference/st_as_binary.html),
[`wk::as_wkb()`](https://paleolimbot.github.io/wk/reference/wkb.html) or
`geos::geos_write_wkb()` return), EWKB with an SRID, hex WKB as
databases return it, or well-known text. Every element is checked by
parsing it. WKB is stored as ISO little-endian WKB; WKT is stored
exactly as given.

## Usage

``` r
geo_vctr(x, crs = NULL, edges = NULL)

is_geo_vctr(x)
```

## Arguments

- x:

  A list of raw vectors (`NULL` for null), a character vector of WKT or
  hex WKB (`NA` for null), an Arrow array handle of a GeoArrow field, or
  a `geo_vctr`.

- crs:

  `NULL`, or anything
  [`geo_crs()`](https://pedrobtz.github.io/zugeo/reference/geo_crs.md)
  takes. Only for WKB and WKT.

- edges:

  `NULL` for planar, or one of `"planar"`, `"spherical"`, `"vincenty"`,
  `"thomas"`, `"andoyer"` and `"karney"`. Only for WKB and WKT.

## Value

A `geo_vctr`.

## Details

The CRS is `crs` when given, else the input's `crs` attribute (as
[`geo_as_wkb()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md)
sets), else an EWKB SRID, which becomes a CRS of `crs_type = "srid"`.
Elements with differing SRIDs are a `zugeo_crs_error`. A CRS is never
looked up or guessed.

## Examples

``` r
geo_vctr(c("POINT (1 2)", NA), crs = "OGC:CRS84")
#> <geo_vctr[2] geoarrow.wkt wkt; crs authority_code; edges planar>
#> [1] POINT (1 2)
#> [2] <null>
geo_vctr(list(as.raw(c(1, 1, 0, 0, 0, rep(0, 16)))))
#> <geo_vctr[1] geoarrow.wkb wkb; crs none; edges planar>
#> [1] POINT (0 0)
is_geo_vctr(1)
#> [1] FALSE
```
