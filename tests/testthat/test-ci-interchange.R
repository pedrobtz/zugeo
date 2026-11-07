# Interchange by WKB with sf, geos, s2 and wk (design section 6.6, Stage 3).
# None of them is a dependency: this file is left out of the package tarball
# (.Rbuildignore) and runs from the source tree, in CI by oracles.yaml.
# Comparisons are by WKB, never by WKT text: sf::st_as_text() prints 7
# significant digits by default.

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

test_that("sf reads geo_as_wkb() and zugeo reads sf's WKB, value for value", {
  skip_without_oracle("sf")
  x <- geo_vctr(interchange_wkt)
  sfc <- sf::st_as_sfc(bare_wkb(x))
  expect_length(sfc, length(interchange_wkt))
  # Element by element: st_as_binary() of a whole sfc with mixed XY and XYZ
  # writes the XYZ point as XY (sf 1.1), which st_as_sfc() had read right.
  wkb <- lapply(seq_along(sfc), function(i) unclass(sf::st_as_binary(sfc[i], EWKB = FALSE))[[1]])
  back <- geo_vctr(wkb)
  expect_identical(bare_wkb(back), bare_wkb(x))
})

test_that("sf keeps the CRS through geo_crs_text(), PROJJSON included (Q5)", {
  skip_without_oracle("sf")
  for (crs in c("OGC:CRS84", "EPSG:4326", "EPSG:3857")) {
    x <- geo_vctr("POINT (1 2)", crs = crs)
    sfc <- sf::st_as_sfc(bare_wkb(x), crs = geo_crs_text(x))
    expect_equal(sf::st_crs(sfc), sf::st_crs(crs), label = crs)
  }
  # PROJJSON as geo_crs_text() writes it, compact: GeoArrow's own example
  # (extension-types.md), WGS 84 with its EPSG id.
  projjson <- paste0(
    '{"$schema":"https://proj.org/schemas/v0.4/projjson.schema.json",',
    '"type":"GeographicCRS","name":"WGS 84","datum":{"type":"GeodeticReferenceFrame",',
    '"name":"World Geodetic System 1984","ellipsoid":{"name":"WGS 84",',
    '"semi_major_axis":6378137,"inverse_flattening":298.257223563}},',
    '"coordinate_system":{"subtype":"ellipsoidal","axis":[{"name":"Longitude",',
    '"abbreviation":"lon","direction":"east","unit":"degree"},{"name":"Latitude",',
    '"abbreviation":"lat","direction":"north","unit":"degree"}]},',
    '"id":{"authority":"EPSG","code":4326}}'
  )
  x <- geo_vctr("POINT (1 2)", crs = projjson)
  expect_identical(geo_crs(x)$type, "projjson")
  crs <- sf::st_crs(geo_crs_text(x))
  expect_false(is.na(crs))
  expect_true(crs$IsGeographic)
  # PROJ finds no EPSG code in it, but the CRS is the same one.
  expect_true(crs == sf::st_crs(4326))
})

test_that("geos reads geo_as_wkb() and zugeo reads geos's WKB", {
  skip_without_oracle("geos")
  x <- geo_vctr(interchange_wkt)
  g <- geos::geos_read_wkb(bare_wkb(x))
  expect_length(g, length(interchange_wkt))
  back <- geo_vctr(unclass(geos::geos_write_wkb(g, include_z = TRUE)))
  expect_identical(geo_coords(back), geo_coords(x))
})

test_that("s2 reads geo_as_wkb() of points and polygons on the sphere", {
  skip_without_oracle("s2")
  x <- geo_vctr(c("POINT (30 10)", "LINESTRING (30 10, 10 30, 40 40)", "POLYGON ((0 0, 10 0, 0 10, 0 0))"),
    crs = "OGC:CRS84", edges = "spherical")
  # s2 reads all WKB as spherical, so the edge type WKB drops is the one s2
  # assumes: passing it on is allowed explicitly.
  s <- s2::s2_geog_from_wkb(bare_wkb(x, lossy = "allow"))
  expect_length(s, 3L)
  back <- geo_vctr(unclass(s2::s2_as_binary(s)))
  expect_equal(geo_coords(back)$x, geo_coords(x)$x, tolerance = 1e-12)
})

test_that("wk reads geo_as_wkb() and zugeo reads wk's WKB", {
  skip_without_oracle("wk")
  x <- geo_vctr(interchange_wkt)
  w <- wk::new_wk_wkb(bare_wkb(x))
  # Coordinates, not wk's WKT: wk 0.9.5 prints the largest double as `inf`
  # when it comes from WKB, though the value it holds is exact.
  coords <- wk::wk_coords(w)
  ours <- geo_coords(x)
  expect_identical(coords$x, ours$x)
  expect_identical(coords$y, ours$y)
  back <- unclass(wk::as_wkb(wk::wkt(interchange_wkt)))
  attributes(back) <- NULL
  expect_identical(geo_coords(geo_vctr(back)), geo_coords(x))
})
