# Report what is wrong with a GeoParquet file

One row per finding (design section 6.11), the checks `gpq validate`
makes and those GeoParquet 2.0 adds. Errors break the specification: a
missing or malformed `geo` key (`geo_key_missing`, `geo_key_invalid`,
`version_invalid`, `primary_column_invalid`, `columns_invalid`,
`primary_column_not_in_columns`), a column entry that breaks the schema
(`encoding_invalid`, `geometry_types_invalid`, `crs_invalid`,
`orientation_invalid`, `edges_invalid`, `bbox_invalid`,
`epoch_invalid`), a geometry column that is missing, nested, repeated or
not `BYTE_ARRAY` (`column_missing`, `column_grouped`, `column_repeated`,
`column_not_byte_array`), a 2.0 column without the native type
(`native_type_missing`) or not in the `geo` key (`column_undeclared`),
and the `geo` key and native type disagreeing (`crs_mismatch`,
`edges_mismatch`, `crs_key_missing`). The data scan adds WKB that does
not parse (`wkb_invalid`), types the metadata does not list
(`geometry_type_undeclared`), rings against a declared orientation
(`orientation_wrong`), geometries outside the `geo` key's `bbox`
(`bbox_exceeded`), and row groups whose native statistics miss their
data (`statistics_exceeded`, `statistics_types`).

## Usage

``` r
geo_validate_parquet(path, metadata_only = FALSE)
```

## Arguments

- path:

  A Parquet file path.

- metadata_only:

  `TRUE` to skip the data scan, as `gpq validate --metadata-only` does.

## Value

A data frame of `column` (`NA` for the file), `row_group` and `row`
(`NA` when the finding is not about one), `issue`, `severity` (`"error"`
or `"warning"`) and `message`; no rows when nothing is wrong.

## Details

Warnings are geometries that are not valid simple features, as
[`geo_validate()`](https://pedrobtz.github.io/zugeo/reference/geo_validate.md)
reports them (winding only where `orientation` is declared), and the
advice of the GeoParquet distribution guide that the file shows:
compression other than zstd (`not_zstd`), row groups over 200,000 rows
(`row_group_large`), and row groups whose boxes overlap so much that the
data cannot be spatially ordered (`not_spatially_ordered`). The `crs` is
checked to be a JSON object or `null`, not validated against the
PROJJSON schema. Needs the qio package.

## See also

[`geo_validate()`](https://pedrobtz.github.io/zugeo/reference/geo_validate.md),
[`geo_parquet_info()`](https://pedrobtz.github.io/zugeo/reference/geo_parquet_info.md)

## Examples

``` r
path <- tempfile(fileext = ".parquet")
geo_write_parquet(geo_points(1:3, 1:3, crs = "OGC:CRS84"), path)
geo_validate_parquet(path)
#> [1] column    row_group row       issue     severity  message  
#> <0 rows> (or 0-length row.names)
```
