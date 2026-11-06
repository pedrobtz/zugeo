# geo_vctr fixtures that need no corpus.
union_path <- function() test_path("data", "geometry-union.arrows")

union_vctr <- function() zuarrow::arrow_read(union_path())$geom

# Writes a data frame to an IPC stream file and reads it back.
round_trip <- function(df) {
  path <- withr::local_tempfile(fileext = ".arrows", .local_envir = parent.frame())
  zuarrow::arrow_write(df, path)
  zuarrow::arrow_read(path)
}

# The field schema of column `name` in an IPC file, as zuarrow reads it.
field_type <- function(path, name = "geometry") {
  geo_type_of(zuarrow::arrow_schema(zuarrow::arrow_read(path, lazy = TRUE)))[[name]]
}
