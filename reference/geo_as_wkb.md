# Convert geometries between encodings

`geo_as_wkb()` gives well-known binary as a list of raw vectors, ISO and
little-endian, `NULL` for a null geometry;
[`sf::st_as_sfc()`](https://r-spatial.github.io/sf/reference/st_as_sfc.html),
`geos::geos_read_wkb()` and
[`s2::s2_geog_from_wkb()`](https://r-spatial.github.io/s2/reference/s2_geog_point.html)
each read it directly. `geo_as_wkt()` gives well-known text, with every
coordinate written as the shortest text that reads back to the same
double, so the round trip is exact. Both carry the CRS as the attribute
`crs`, since bare WKB and WKT have no place for one (design section
6.3).

## Usage

``` r
geo_as_wkb(x, lossy = c("error", "warn", "allow"))

geo_as_wkt(x, lossy = c("error", "warn", "allow"))

geo_as_native(x, layout = c("separated", "interleaved"), type = NULL)
```

## Arguments

- x:

  A `geo_vctr`.

- lossy:

  What to do when the conversion would lose information: a non-planar
  edge type on geometries with edges, which WKB and WKT cannot carry.
  `"error"` (a `zugeo_edges_error`), `"warn"` (a `zugeo_edges_warning`)
  or `"allow"`. The CRS is never lost: it rides as the `crs` attribute.

- layout:

  `"separated"` (a struct of coordinate arrays, as GeoArrow advises) or
  `"interleaved"`.

- type:

  `NULL` to infer, or one of `"point"`, `"linestring"`, `"polygon"`,
  `"multipoint"`, `"multilinestring"` and `"multipolygon"`; needed when
  every geometry is null.

## Value

`geo_as_wkb()`: a list of raw vectors; `geo_as_wkt()`: a character
vector; `geo_as_native()`: a `geo_vctr`.

## Details

`geo_as_native()` gives a `geo_vctr` in a GeoArrow native type. The type
is the one the geometries share, a single type promoted to its multi
type where both appear; mixed types and geometry collections need WKB or
WKT.

## See also

[`geo_vctr()`](https://pedrobtz.github.io/zugeo/reference/geo_vctr.md)
for the reverse,
[`geo_crs_text()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_text.md).

## Examples

``` r
x <- geo_vctr(c("POINT (1 2)", "LINESTRING (0 0, 1 1)", NA))
geo_as_wkt(x)
#> [1] "POINT (1 2)"           "LINESTRING (0 0, 1 1)" NA                     
#> attr(,"crs")
#> <zugeo_crs: none>
lengths(geo_as_wkb(x))
#> [1] 21 41  0
```
