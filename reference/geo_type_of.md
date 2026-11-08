# Describe a GeoArrow field

Reads what an Arrow schema says about a GeoArrow field: the extension
name, its encoding and layout, and its CRS and edges from the extension
metadata. Every GeoArrow 0.2 extension name is understood, in both
coordinate layouts, with `list` or `large_list` offsets and the view
storage types (design section 6.2). A layout the specification forbids
is a `zugeo_layout_error`; malformed metadata is a
`zugeo_metadata_error`.

## Usage

``` r
geo_type_of(x)
```

## Arguments

- x:

  An Arrow schema, array or stream handle, from zuarrow or nanoarrow, or
  a `geo_vctr`. A field with a `geoarrow.*` extension name is described
  directly; a struct, such as a stream's schema, has each of its
  GeoArrow fields described.

## Value

A `zugeo_type`, a list of `extension`, `encoding` (`"native"`, `"wkb"`,
`"wkt"` or `"box"`), `geometry_type`, `dimensions` (`NA` when the
storage does not fix them), `coord_type` (`"separated"`,
`"interleaved"`, `"mixed"` or `NA`), `offsets` (one entry per list
level, outer first), `storage` (the Arrow format string), `union_ids`,
`crs` (a `zugeo_crs`), `edges` and `metadata` (the extension metadata
exactly as given, or `NA`). For a struct, a named list of them.

## Examples

``` r
x <- geo_vctr("POINT (1 2)", crs = "OGC:CRS84")
geo_type_of(x)
#> <geoarrow.wkt wkt; crs authority_code; edges planar>
geo_type_of(geo_as_native(x))$coord_type
#> [1] "separated"
```
