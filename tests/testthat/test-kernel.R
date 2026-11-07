test_that("geo_box() bounds each geometry over its coordinates", {
  x <- geo_vctr(c("POINT (1 2)", "LINESTRING Z (0 0 1, 3 4 5)", NA, "POLYGON EMPTY", "POINT EMPTY"),
    crs = "OGC:CRS84")
  b <- geo_box(x)
  expect_s3_class(b, "geo_extent")
  expect_named(b, c("xmin", "ymin", "xmax", "ymax", "zmin", "zmax"))
  expect_identical(b$xmin, c(1, 0, NA, NaN, NaN))
  expect_identical(b$ymax, c(2, 4, NA, NaN, NaN))
  expect_identical(b$zmax, c(NaN, 5, NA, NaN, NaN))
  expect_true(geo_crs_equal(attr(b, "crs"), "OGC:CRS84"))
  all <- geo_box_all(x)
  expect_length(all, 1L)
  expect_identical(unlist(as.data.frame(all)), c(xmin = 0, ymin = 0, xmax = 3, ymax = 4, zmin = 1, zmax = 5))
  m <- geo_box(geo_vctr("MULTIPOINT M ((1 2 3), (4 5 6))"))
  expect_named(m, c("xmin", "ymin", "xmax", "ymax", "mmin", "mmax"))
  expect_identical(c(m$mmin, m$mmax), c(3, 6))
})

test_that("geo_box() works over unions, interleaved and large lists alike", {
  g <- union_vctr()
  b <- geo_box(g)
  expect_identical(b$xmax, c(1, 1, 3, 5, -1, 6))
  expect_identical(b$zmin, c(NaN, NaN, 5, NaN, -3, NaN))
  p <- geo_as_native(geo_vctr(c("POLYGON ((0 0, 4 0, 0 4, 0 0))", "POLYGON ((1 1, 2 1, 1 2, 1 1))")), "interleaved")
  expect_identical(geo_box(p)$xmax, c(4, 2))
  big <- zgo_vctr_new(1L, attr(geo_as_native(geo_vctr("LINESTRING (0 0, 9 9)")), "chunks"),
    attr(geo_as_native(geo_vctr("LINESTRING (0 0, 9 9)")), "schema"))
  expect_identical(geo_box(big)$xmax, 9)
})

test_that("a planar box of non-planar edges needs lossy", {
  x <- geo_vctr("LINESTRING (0 0, 170 0)", edges = "spherical")
  expect_error(geo_box(x), class = "zugeo_edges_error")
  expect_warning(b <- geo_box(x, lossy = "warn"), class = "zugeo_edges_warning")
  expect_identical(b$xmax, 170)
  expect_silent(geo_box(x, lossy = "allow"))
  # Points have no edges, so their boxes are exact on any edge type.
  expect_silent(geo_box(geo_vctr("MULTIPOINT ((0 0), (1 1))", edges = "spherical")))
})

test_that("types, dimensions and coordinate counts per geometry", {
  x <- geo_vctr(c("POINT (1 2)", "MULTILINESTRING Z ((0 0 1, 1 1 1), (2 2 2, 3 3 3, 4 4 4))",
    NA, "GEOMETRYCOLLECTION M (POINT M (1 2 3))", "POINT EMPTY", "POLYGON ZM ((0 0 0 0, 1 0 0 0, 0 1 0 0, 0 0 0 0))"))
  expect_identical(geo_types(x), c("point", "multilinestring", NA, "geometrycollection", "point", "polygon"))
  expect_identical(geo_dims(x), c("xy", "xyz", NA, "xym", "xy", "xyzm"))
  expect_identical(geo_n_coords(x), c(1L, 5L, NA, 1L, 0L, 4L))
})

test_that("geo_hilbert() gives flatbush's keys exactly", {
  f <- read.csv(test_path("data", "hilbert-flatbush.csv"))
  wkt <- sprintf("POLYGON ((%.17g %.17g, %.17g %.17g, %.17g %.17g, %.17g %.17g, %.17g %.17g))",
    f$xmin, f$ymin, f$xmax, f$ymin, f$xmax, f$ymax, f$xmin, f$ymax, f$xmin, f$ymin)
  expect_identical(geo_hilbert(geo_vctr(wkt)), as.double(f$key))
})

test_that("geo_hilbert() takes an extent; geo_sort() orders, nulls last", {
  p <- geo_points(c(5, 1, 3, 2), c(5, 1, 3, 9))
  k <- geo_hilbert(p)
  expect_type(k, "double")
  expect_true(all(k >= 0 & k < 2^32))
  x <- c(p, geo_points(NaN, NaN), p[1])
  keys <- geo_hilbert(geo_vctr(c("POINT (5 5)", "POINT EMPTY", NA, "POINT (1 1)")))
  expect_identical(is.na(keys), c(FALSE, TRUE, TRUE, FALSE))
  s <- geo_sort(geo_vctr(c("POINT (5 5)", NA, "POINT (1 1)", "POINT (5 5)")))
  expect_identical(s, c(3L, 1L, 4L, 2L))
  e <- geo_extent(0, 0, 10, 10)
  expect_identical(geo_hilbert(geo_points(c(-5, 0), c(-5, 0)), extent = e)[1],
    geo_hilbert(geo_points(c(-5, 0), c(-5, 0)), extent = e)[2])
  expect_error(geo_hilbert(p, extent = c(e, e)), class = "zugeo_error")
  expect_identical(geo_hilbert(geo_vctr(c(NA, NA))), c(NA_real_, NA_real_))
  expect_error(geo_sort(p, by = "morton"))
})

test_that("extents combine, subset and print", {
  e <- geo_extent(c(0, 5), c(0, 5), c(2, 6), c(2, 6), crs = "OGC:CRS84")
  expect_length(e, 2L)
  expect_identical(e[2]$xmin, 5)
  expect_identical(format(e), c("[0 0, 2 2]", "[5 5, 6 6]"))
  expect_output(print(e), "<geo_extent\\[2\\]; crs authority_code: OGC:CRS84")
  both <- c(e, e[1])
  expect_length(both, 3L)
  expect_identical(nrow(as.data.frame(both)), 3L)
  expect_error(c(e, geo_extent(0, 0, 1, 1)), class = "zugeo_crs_error")
  expect_error(c(e, geo_extent(0, 0, 1, 1, 0, 1, crs = "OGC:CRS84")), "dimensions")
  expect_error(geo_extent(0, 0, 1, 1, zmin = 0), "pairs")
  expect_error(geo_extent("a", 0, 1, 1), "numeric")
  expect_identical(is.na(geo_extent(c(NA, NaN, 1), 0, 1, 1)), c(TRUE, FALSE, FALSE))
  expect_identical(format(geo_extent(NA, NA, NA, NA)), "<null>")
})

test_that("extent set operations, with nulls and empties disjoint", {
  e <- geo_extent(c(0, 5, NA, NaN), c(0, 5, NA, NaN), c(2, 6, NA, NaN), c(2, 6, NA, NaN))
  u <- geo_extent_union(e)
  expect_identical(unlist(as.data.frame(u)), c(xmin = 0, ymin = 0, xmax = 6, ymax = 6))
  f <- geo_extent(1, 1, 5.5, 5.5)
  expect_identical(geo_extent_intersects(e, f), c(TRUE, TRUE, FALSE, FALSE))
  i <- geo_extent_intersection(e, f)
  expect_identical(i$xmin, c(1, 5, NA, NaN))
  expect_identical(i$xmax, c(2, 5.5, NA, NaN))
  apart <- geo_extent_intersection(geo_extent(0, 0, 1, 1), geo_extent(2, 2, 3, 3))
  expect_true(is.nan(apart$xmin))
  expect_false(geo_extent_intersects(geo_extent(0, 0, 1, 1), geo_extent(2, 2, 3, 3)))
  # Touching boxes intersect.
  expect_true(geo_extent_intersects(geo_extent(0, 0, 1, 1), geo_extent(1, 1, 2, 2)))
  # Z counts where both have it.
  z1 <- geo_extent(0, 0, 1, 1, 0, 1)
  z2 <- geo_extent(0, 0, 1, 1, 5, 6)
  expect_false(geo_extent_intersects(z1, z2))
  expect_true(geo_extent_intersects(z1, geo_extent(0, 0, 1, 1)))
  expect_true(is.nan(geo_extent_union(geo_extent(NA, NA, NA, NA))$xmin))
  # An antimeridian box is refused, never read as planar.
  wrap <- geo_extent(170, 0, -170, 10)
  expect_error(geo_extent_union(wrap), class = "zugeo_edges_error")
  expect_error(geo_extent_intersects(wrap, f), class = "zugeo_edges_error")
  expect_error(geo_extent_intersects(f, geo_extent(0, 0, 1, 1, crs = "OGC:CRS84")),
    class = "zugeo_crs_error")
  expect_error(geo_extent_union(1), class = "zugeo_error")
})

test_that("geo_validate() reports and never repairs", {
  x <- geo_vctr(c(
    "POLYGON ((0 0, 1 0, 0 1))",
    "POLYGON ((0 0, 0 1, 1 0, 0 0))",
    "POLYGON ((0 0, 4 0, 0 4, 0 0), (1 1, 2 1, 1 2, 1 1))",
    "POINT (1 2)", "LINESTRING (1 1)", "POINT EMPTY",
    "LINESTRING (0 0, 1 1)",
    "GEOMETRYCOLLECTION (POINT (1 2), POINT Z (1 2 3))", NA
  ))
  v <- geo_validate(x)
  expect_named(v, c("row", "issue", "part", "ring"))
  expect_identical(v$issue[v$row == 1], c("unclosed_ring", "short_ring"))
  expect_identical(v$issue[v$row == 2], "exterior_clockwise")
  expect_identical(v$issue[v$row == 3], "interior_counterclockwise")
  expect_identical(v$ring[v$row == 3], 2L)
  expect_identical(v$issue[v$row == 5], "short_linestring")
  expect_identical(v$issue[v$row == 8], "mixed_dimensions")
  expect_false(any(v$row %in% c(4L, 6L, 7L, 9L)))
  # A non-finite coordinate, which only native or WKB input can carry.
  inf <- geo_points(c(1, Inf), c(2, 3))
  expect_identical(geo_validate(inf)$issue, "non_finite")
  expect_identical(nrow(geo_validate(geo_vctr("POINT (1 2)"))), 0L)
  # Validation reads; the vector is unchanged.
  expect_identical(as.vector(geo_as_wkt(x))[1], "POLYGON ((0 0, 1 0, 0 1))")
})
