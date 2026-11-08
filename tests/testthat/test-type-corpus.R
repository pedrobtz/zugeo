# Stage 1's exit criterion: every geoarrow-data schema described correctly.
# The expected description comes from the file name:
# example_<type>[-<variant>][_<encoding>].arrows.

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
