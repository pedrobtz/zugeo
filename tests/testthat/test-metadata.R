type_with <- function(metadata) geo_type_of(ga_schema("point", metadata = metadata))

test_that("metadata keeps the CRS exactly as given, typed", {
  projjson <- '{"crs": {"type": "GeographicCRS", "name": "WGS 84", "id": {"authority": "EPSG", "code": 4326}}}'
  t <- type_with(projjson)
  expect_identical(t$crs$type, "projjson")
  expect_identical(t$crs$value$id$code, 4326L)
  expect_identical(t$metadata, projjson)

  t <- type_with('{"crs": "EPSG:4326", "crs_type": "authority_code"}')
  expect_identical(t$crs$value, "EPSG:4326")
  expect_identical(t$crs$type, "authority_code")

  # A string with no crs_type stays untyped: never guessed.
  t <- type_with('{"crs": "EPSG:4326"}')
  expect_identical(t$crs$type, NA_character_)

  t <- type_with('{"crs": null}')
  expect_null(t$crs$value)
  expect_null(type_with("{}")$crs$value)
  expect_null(type_with(NULL)$crs$value)
})

test_that("edges are read, planar when absent", {
  expect_identical(type_with(NULL)$edges, "planar")
  for (edges in c("planar", "spherical", "vincenty", "thomas", "andoyer", "karney")) {
    expect_identical(type_with(sprintf('{"edges": "%s"}', edges))$edges, edges)
  }
})

test_that("malformed metadata is a metadata error", {
  bad <- c(
    "{not json",
    "[1, 2]",
    '"crs"',
    '{"crs": 4326}',
    '{"crs": "x", "crs_type": "epsg"}',
    '{"crs": {"type": "GeographicCRS"}, "crs_type": "wkt2:2019"}',
    '{"crs": "x", "crs_type": "projjson"}',
    '{"edges": "geodesic"}',
    '{"edges": 1}'
  )
  for (metadata in bad) {
    expect_error(type_with(metadata), class = "zugeo_metadata_error", label = metadata)
  }
})
