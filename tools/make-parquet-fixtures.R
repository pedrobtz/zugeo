#!/usr/bin/env Rscript
# Parquet fixtures no zugeo or qio writer can produce, written once with
# DuckDB and committed (tests/testthat/data/). Re-run from the package root
# only to regenerate them:
#
#   Rscript tools/make-parquet-fixtures.R
#
# geo-grouped.parquet: a geo key naming `geometry` as WKB over a struct
# column of that name, which GeoParquet forbids (geometry columns are not
# grouped): geo_validate_parquet()'s column_grouped.
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
geo <- paste0(
  '{"version":"1.1.0","primary_column":"geometry","columns":',
  '{"geometry":{"encoding":"WKB","geometry_types":[]}}}'
)
DBI::dbExecute(con, sprintf(paste(
  "COPY (SELECT 1 AS id, {'wkb': '\\x01'::BLOB} AS geometry)",
  "TO 'tests/testthat/data/geo-grouped.parquet' (FORMAT parquet, KV_METADATA {geo: '%s'})"
), geo))
