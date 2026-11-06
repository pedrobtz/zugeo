# Stage 1's exit criterion: every geoarrow-data schema described correctly.
# The expected description comes from the file name:
# example_<type>[-<variant>][_<encoding>].arrows.

corpus_expected <- function(file) {
  base <- sub("^example_", "", sub("[.]arrows$", "", file))
  encoding <- if (grepl("_", base)) sub("^.*_", "", base) else "native"
  stem <- sub("_.*$", "", base)
  type <- sub("-.*$", "", stem)
  variant <- if (grepl("-", stem)) sub("^[^-]*-", "", stem) else ""
  dims <- c(z = "xyz", m = "xym", zm = "xyzm")[variant]
  levels <- c(point = 0L, linestring = 1L, polygon = 2L, multipoint = 1L,
    multilinestring = 2L, multipolygon = 3L)[type]
  serialized <- encoding %in% c("wkb", "wkt")
  list(
    extension = if (serialized) paste0("geoarrow.", encoding) else paste0("geoarrow.", type),
    encoding = if (serialized) encoding else "native",
    geometry_type = if (serialized) "geometry" else type,
    dimensions = if (serialized) NA_character_ else if (is.na(dims)) "xy" else unname(dims),
    coord_type = if (serialized) NA_character_ else if (encoding == "interleaved") "interleaved" else "separated",
    n_offsets = if (serialized) 0L else unname(levels)
  )
}

test_that("every geoarrow-data schema is described correctly", {
  files <- names(corpus_manifest())
  expect_length(files, 122L)
  for (file in files) {
    type <- geo_type_of(corpus_schema(file))
    expect_named(type, "geometry", label = file)
    type <- type$geometry
    want <- corpus_expected(file)
    got <- list(
      extension = type$extension,
      encoding = type$encoding,
      geometry_type = type$geometry_type,
      dimensions = type$dimensions,
      coord_type = type$coord_type,
      n_offsets = length(type$offsets)
    )
    expect_identical(got, want, label = file)
    expect_true(all(type$offsets == "list"), label = file)
    expect_null(type$crs$value, label = file)
    expect_identical(type$edges, "planar", label = file)
  }
})
