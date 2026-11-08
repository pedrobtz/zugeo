test_that("WKT reads exactly as given and writes back exactly", {
  wkt <- c("POINT (1 2)", "LINESTRING (0 0, 1 1)", NA, "POLYGON EMPTY")
  x <- geo_vctr(wkt)
  expect_identical(geo_type_of(x)$extension, "geoarrow.wkt")
  expect_identical(as.vector(geo_as_wkt(x)), wkt)
  expect_identical(is.na(x), c(FALSE, FALSE, TRUE, FALSE))
})

test_that("WKB reads, normalises to ISO little-endian, and writes back", {
  x <- geo_vctr(c("POINT Z (1 2 3)", "MULTILINESTRING ((0 0, 1 1), (2 2, 3 3))", NA))
  wkb <- geo_as_wkb(x)
  expect_type(wkb, "list")
  expect_null(wkb[[3]])
  expect_identical(wkb[[1]][1], as.raw(1))
  y <- geo_vctr(wkb)
  expect_identical(geo_type_of(y)$extension, "geoarrow.wkb")
  expect_identical(as.vector(geo_as_wkt(y)), as.vector(geo_as_wkt(x)))
  # Big-endian WKB reads too, and is written back little-endian.
  big <- c(as.raw(0), writeBin(1L, raw(), size = 4, endian = "big"),
    writeBin(c(1, 2), raw(), size = 8, endian = "big"))
  z <- geo_vctr(list(big))
  expect_identical(as.vector(geo_as_wkt(z)), "POINT (1 2)")
  expect_identical(geo_as_wkb(z)[[1]][1], as.raw(1))
})

test_that("hex WKB reads as WKB", {
  wkb <- geo_as_wkb(geo_vctr("POINT (1 2)"))[[1]]
  hex <- paste(as.character(wkb), collapse = "")
  for (text in c(hex, toupper(hex))) {
    x <- geo_vctr(c(text, NA))
    expect_identical(geo_type_of(x)$extension, "geoarrow.wkb")
    expect_identical(as.vector(geo_as_wkt(x)), c("POINT (1 2)", NA))
  }
})

test_that("an EWKB SRID becomes the CRS, typed srid, never dropped", {
  x <- geo_vctr(list(ewkb_point(1, 2, 4326), NULL, ewkb_point(3, 4, 4326)))
  expect_identical(geo_crs(x)$value, "4326")
  expect_identical(geo_crs(x)$type, "srid")
  expect_identical(as.vector(geo_as_wkt(x)), c("POINT (1 2)", NA, "POINT (3 4)"))
  # The stored WKB is ISO: no SRID flag left.
  expect_identical(geo_as_wkb(x)[[1]][2:5], writeBin(1L, raw(), size = 4, endian = "little"))
  expect_error(
    geo_vctr(list(ewkb_point(1, 2, 4326), ewkb_point(1, 2, 3857))),
    "differing SRIDs",
    class = "zugeo_crs_error"
  )
  expect_error(
    geo_vctr(list(ewkb_point(1, 2, 4326), geo_as_wkb(geo_vctr("POINT (1 2)"))[[1]])),
    class = "zugeo_crs_error"
  )
  # crs = wins over the SRID.
  y <- geo_vctr(list(ewkb_point(1, 2, 4326)), crs = "EPSG:4326")
  expect_identical(geo_crs(y)$type, "authority_code")
})

test_that("the CRS and edges reach the metadata and come back", {
  projjson <- '{"type": "GeographicCRS", "name": "WGS 84", "id": {"authority": "EPSG", "code": 4326}}'
  x <- geo_vctr("POINT (1 2)", crs = projjson, edges = "spherical")
  type <- geo_type_of(x)
  expect_identical(type$crs$type, "projjson")
  expect_identical(type$edges, "spherical")
  expect_true(geo_crs_equal(x, projjson))
  # The CRS rides on WKB through the attribute.
  y <- geo_vctr(geo_as_wkb(x), edges = "spherical")
  expect_true(geo_crs_equal(y, x))
  expect_true(is.na(geo_type_of(geo_vctr("POINT (1 2)"))$metadata))
  expect_identical(geo_type_of(geo_vctr("POINT (1 2)", crs = "4326"))$crs$type, NA_character_)
  expect_error(geo_vctr("POINT (1 2)", edges = "geodesic"), class = "zugeo_error")
})

test_that("geo_crs_text() gives one string for other packages", {
  projjson <- '{"type": "GeographicCRS", "name": "WGS 84"}'
  expect_identical(geo_crs_text(geo_vctr("POINT (1 2)", crs = projjson)),
    '{"type":"GeographicCRS","name":"WGS 84"}')
  expect_identical(geo_crs_text(geo_vctr("POINT (1 2)", crs = "OGC:CRS84")), "OGC:CRS84")
  expect_identical(geo_crs_text(geo_vctr("POINT (1 2)")), NA_character_)
})

test_that("malformed WKB and WKT are errors naming the element", {
  expect_error(geo_vctr(c("POINT (1 2)", "POINT (1")), "Element 2 is not valid WKT")
  expect_error(geo_vctr("POINT (1 1e400)"), "not valid WKT")
  expect_error(geo_vctr(list(as.raw(1:3))), "Element 1 is not valid WKB")
  expect_error(geo_vctr(list(1:3)), "list of raw vectors")
  expect_error(geo_vctr("0101"), "not valid WKB")
  expect_error(geo_vctr(1), class = "zugeo_error")
  expect_error(geo_vctr(geo_vctr("POINT (1 2)"), crs = "x"), class = "zugeo_error")
  # Every truncation of valid WKB is an error, never a crash.
  wkb <- geo_as_wkb(geo_vctr("MULTIPOLYGON (((0 0, 1 0, 0 1, 0 0)), ((5 5, 6 5, 5 6, 5 5)))"))[[1]]
  for (n in seq_len(length(wkb) - 1L) - 1L) {
    expect_error(geo_vctr(list(wkb[seq_len(n)])), "not valid WKB", label = n)
  }
  # And every truncation of valid WKT that is not itself valid.
  text <- "POLYGON ((0 0, 1 0, 0 1, 0 0), (0.1 0.1, 0.2 0.1, 0.1 0.2, 0.1 0.1))"
  for (n in seq_len(nchar(text) - 1L)) {
    expect_error(geo_vctr(substr(text, 1L, n)), "not valid WKT", label = n)
  }
})

test_that("geo_as_native() refuses a type that would reshape the geometries", {
  mp <- geo_vctr("MULTIPOLYGON (((0 0, 1 0, 0 1, 0 0)), ((5 5, 6 5, 5 6, 5 5)))")
  expect_error(geo_as_native(mp, type = "polygon"), class = "zugeo_layout_error")
  expect_error(
    geo_as_native(geo_vctr("POLYGON ((0 0, 1 0, 0 1, 0 0))"), type = "linestring"),
    class = "zugeo_layout_error"
  )
  expect_error(
    geo_as_native(geo_vctr("POINT (1 1)"), type = "polygon"),
    class = "zugeo_layout_error"
  )
  # The single type promotes to its multi type, and the multi type stays.
  p <- geo_as_native(geo_vctr(c("POINT (1 1)", NA)), type = "multipoint")
  expect_identical(geo_coords(p)[c("x", "y")], data.frame(x = 1, y = 1))
  expect_identical(geo_types(p), c("multipoint", NA))
  expect_identical(geo_as_wkt(geo_as_native(mp, type = "multipolygon")), geo_as_wkt(mp))
})

test_that("geo_as_native() infers one type, promoting to multi", {
  x <- geo_vctr(c("POLYGON ((0 0, 1 0, 0 1, 0 0))", NA,
    "MULTIPOLYGON (((0 0, 2 0, 0 2, 0 0)), ((5 5, 6 5, 5 6, 5 5)))"))
  n <- geo_as_native(x)
  expect_identical(geo_type_of(n)$extension, "geoarrow.multipolygon")
  expect_identical(geo_type_of(n)$coord_type, "separated")
  expect_identical(is.na(n), c(FALSE, TRUE, FALSE))
  expect_identical(geo_as_wkt(n)[3], geo_as_wkt(x)[3])
  i <- geo_as_native(x, "interleaved")
  expect_identical(geo_type_of(i)$coord_type, "interleaved")
  expect_identical(format(i), format(n))
  expect_identical(geo_type_of(geo_as_native(geo_vctr("POINT M (1 2 3)")))$dimensions, "xym")
  p <- geo_as_native(geo_vctr(c(NA, NA)), type = "point")
  expect_identical(geo_type_of(p)$extension, "geoarrow.point")

  expect_error(geo_as_native(geo_vctr(c("POINT (1 2)", "LINESTRING (0 0, 1 1)"))),
    "mix points", class = "zugeo_layout_error")
  expect_error(geo_as_native(geo_vctr("GEOMETRYCOLLECTION (POINT (1 2))")),
    "collections", class = "zugeo_layout_error")
  expect_error(geo_as_native(geo_vctr(c("POINT (1 2)", "POINT Z (1 2 3)"))),
    "mixed dimensions", class = "zugeo_layout_error")
  expect_error(geo_as_native(geo_vctr(NA_character_)), "every geometry is null",
    ignore.case = TRUE, class = "zugeo_layout_error")
  expect_error(geo_as_native(x, type = "box"), class = "zugeo_error")
  expect_error(geo_as_native(1), class = "zugeo_error")
})

test_that("coordinates come out as columns and go back", {
  wkt <- c(
    point = "POINT (1 2)",
    linestring = "LINESTRING Z (0 0 1, 1 1 2)",
    polygon = "POLYGON ((0 0, 4 0, 0 4, 0 0), (1 1, 2 1, 1 2, 1 1))",
    multipoint = "MULTIPOINT M ((1 2 3), (4 5 6))",
    multilinestring = "MULTILINESTRING ((0 0, 1 1), (2 2, 3 3, 4 4))",
    multipolygon = "MULTIPOLYGON (((0 0, 1 0, 0 1, 0 0)), ((5 5, 6 5, 5 6, 5 5), (5.1 5.1, 5.2 5.1, 5.1 5.2, 5.1 5.1)))"
  )
  for (type in names(wkt)) {
    x <- geo_vctr(c(wkt[[type]], wkt[[type]]))
    coords <- geo_coords(x)
    back <- geo_from_coords(coords, type)
    expect_identical(as.vector(geo_as_wkt(back)), as.vector(geo_as_wkt(x)), label = type)
  }
  coords <- geo_coords(geo_vctr(wkt[["polygon"]]))
  expect_named(coords, c("x", "y", "feature", "part", "ring"))
  expect_identical(coords$ring, rep(1:2, each = 4))
  mp <- geo_coords(geo_vctr(wkt[["multipolygon"]]))
  expect_identical(mp$part, rep(1:2, c(4, 8)))
  expect_named(geo_coords(geo_vctr(wkt[["multipoint"]])), c("x", "y", "m", "feature", "part", "ring"))
  # Null and empty geometries have no rows; a feature with no rows is empty.
  e <- geo_coords(geo_vctr(c("POINT EMPTY", NA, "POINT (1 2)")))
  expect_identical(e$feature, 3L)
  pts <- geo_from_coords(e, "point", n = 3)
  expect_identical(as.vector(geo_as_wkt(pts))[3], "POINT (1 2)")
  expect_error(geo_from_coords(data.frame(x = 1, y = 1, feature = 2:1), "linestring"),
    "increasing")
  expect_error(geo_from_coords(data.frame(x = 1:2, y = 1:2, feature = 1L), "point"),
    "more than one")
  expect_error(geo_from_coords(list(x = 1), "point"), class = "zugeo_error")
})

test_that("geo_points() makes points from vectors", {
  p <- geo_points(c(1, 2), c(3, 4), m = c(5, 6), crs = "OGC:CRS84")
  expect_identical(as.vector(geo_as_wkt(p)), c("POINT M (1 3 5)", "POINT M (2 4 6)"))
  expect_identical(geo_crs_text(p), "OGC:CRS84")
  expect_identical(geo_type_of(geo_points(1, 2, layout = "interleaved"))$coord_type, "interleaved")
})

test_that("geo_points() takes coordinates of one length, never recycled", {
  expect_error(geo_points(1:4, 1:2), class = "zugeo_error")
  expect_error(geo_points(1:3, 1:2), class = "zugeo_error")
  expect_error(geo_points(1:2, 1:2, z = 1), class = "zugeo_error")
  expect_error(geo_points("1", 2), class = "zugeo_error")
  expect_length(geo_points(numeric(), numeric()), 0L)
  expect_identical(geo_coords(geo_points(1:2, 3:4, m = 5:6))$m, c(5, 6))
})

test_that("a WKT number takes one sign at most", {
  expect_identical(geo_coords(geo_vctr("POINT (+1 -2)"))$x, 1)
  for (wkt in c("POINT (+-1 2)", "POINT (++1 2)", "POINT (1 +-2)")) {
    expect_error(geo_vctr(wkt), "not valid WKT", label = wkt)
  }
})

test_that("geo_from_coords() reads only columns named exactly", {
  x <- geo_from_coords(
    data.frame(x = 1:2, y = 1:2, mass = c(10, 20), zone = 3:4, feature_id = 2:1),
    "point"
  )
  expect_identical(geo_dims(x), c("xy", "xy"))
  expect_identical(geo_coords(x)$feature, 1:2)
})
