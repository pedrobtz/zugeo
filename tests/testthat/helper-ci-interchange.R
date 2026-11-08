# Shared by test-ci-interchange.R; at file level there, a shuffled run could use it before it was defined.

# A list of raw vectors with no attributes, as wk insists.
bare_wkb <- function(x, lossy = "error") {
  out <- unclass(geo_as_wkb(x, lossy = lossy))
  attributes(out) <- NULL
  out
}
interchange_wkt <- c(
  "POINT (30 10)", "POINT Z (1 2 3)", "LINESTRING (30 10, 10 30, 40 40)",
  "POLYGON ((35 10, 45 45, 15 40, 10 20, 35 10), (20 30, 35 35, 30 20, 20 30))",
  "MULTIPOINT ((10 40), (40 30))", "MULTILINESTRING ((10 10, 20 20), (40 40, 30 30))",
  "MULTIPOLYGON (((30 20, 45 40, 10 40, 30 20)), ((15 5, 40 10, 10 20, 15 5)))",
  "GEOMETRYCOLLECTION (POINT (40 10), LINESTRING (10 10, 20 20))",
  "LINESTRING (0.01234567890123456 1e-20, 1.7976931348623157e+308 -0)"
)
