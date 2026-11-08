# Geometry collections (native and inside a union), box columns, XYZM
# coordinates and the 32-bit index layouts, which neither geoarrow-data nor
# the other fixtures reach. The collection file is
# tools/make-collection-fixture.py's output.

collection_data <- function() {
  zuarrow::arrow_read(test_path("data", "geometry-collection.arrows"))
}

test_that("a native geometrycollection column reads, converts and is measured", {
  g <- collection_data()$gc
  expect_identical(geo_type_of(g)$geometry_type, "geometrycollection")
  expect_identical(
    format(g),
    c("GEOMETRYCOLLECTION (POINT (1 2), LINESTRING (0 0, 3 4))",
      "GEOMETRYCOLLECTION EMPTY", "<null>", "GEOMETRYCOLLECTION (POINT (9 9))")
  )
  expect_identical(geo_types(g), c("geometrycollection", "geometrycollection", NA, "geometrycollection"))
  expect_identical(geo_n_coords(g), c(3L, 0L, NA, 1L))
  box <- as.data.frame(geo_box(g))
  expect_identical(box$xmax, c(3, NaN, NA, 9))
  expect_identical(is.na(g), c(FALSE, FALSE, TRUE, FALSE))
  # Through WKB and WKT and back, value for value, and gathered.
  expect_identical(geo_coords(geo_vctr(geo_as_wkb(g))), geo_coords(g))
  expect_identical(geo_as_wkt(geo_vctr(geo_as_wkt(g))), geo_as_wkt(g))
  expect_identical(format(g[c(4, 1)]), format(g)[c(4, 1)])
  expect_identical(nrow(geo_validate(g)), 0L)
})

test_that("a union holding geometry collections (type id 7) is visited", {
  g <- collection_data()$union
  expect_identical(
    format(g),
    c("POINT (0.5 0.5)", "GEOMETRYCOLLECTION (POINT (5 6), LINESTRING (1 1, 2 2))",
      "GEOMETRYCOLLECTION (POINT (7 8))", "POINT (4 4)")
  )
  expect_identical(geo_types(g), c("point", "geometrycollection", "geometrycollection", "point"))
  expect_identical(as.data.frame(geo_box(g))$ymax, c(0.5, 6, 8, 4))
  expect_identical(geo_coords(geo_vctr(geo_as_wkb(g))), geo_coords(g))
})

test_that("a box column formats each box", {
  b <- collection_data()$box
  expect_identical(
    format(b),
    c("BOX (0 1, 2 3)", "BOX (-1.5 -2.5, 0.25 0.125)", "<null>", "BOX (10 10, 10 10)")
  )
  expect_identical(is.na(b), c(FALSE, FALSE, TRUE, FALSE))
})

test_that("a box column is its own boxes, and refuses the geometry kernels", {
  b <- collection_data()$box
  e <- geo_box(b)
  expect_s3_class(e, "geo_extent")
  expect_identical(
    as.data.frame(e),
    data.frame(xmin = c(0, -1.5, NA, 10), ymin = c(1, -2.5, NA, 10),
      xmax = c(2, 0.25, NA, 10), ymax = c(3, 0.125, NA, 10))
  )
  expect_identical(format(geo_box(b[c(4, 1)])), c("[10 10, 10 10]", "[0 1, 2 3]"))
  # What builds on boxes works; what needs geometries says why it cannot.
  expect_identical(geo_query_box(geo_rtree(b), geo_extent(1, 2, 1.5, 2.5)), 1L)
  expect_identical(length(geo_sort(b)), 4L)
  for (f in list(geo_types, geo_dims, geo_n_coords, geo_validate, geo_coords,
    geo_as_wkb, geo_as_wkt, geo_as_native, geo_kdtree)) {
    expect_error(f(b), class = "zugeo_layout_error")
  }
  expect_snapshot(geo_types(b), error = TRUE)
})

test_that("geo_from_coords() makes XYZM geometries", {
  coords <- data.frame(
    x = c(0, 1, 2), y = c(0, 1, 0), z = c(5, 6, 7), m = c(10, 11, 12), feature = 1L
  )
  g <- geo_from_coords(coords, "linestring")
  expect_identical(geo_dims(g), "xyzm")
  expect_identical(geo_as_wkt(g)[[1L]], "LINESTRING ZM (0 0 5 10, 1 1 6 11, 2 0 7 12)")
  back <- geo_coords(g)
  expect_identical(back[c("x", "y", "z", "m")], coords[c("x", "y", "z", "m")])
})

test_that("indexes past 16,384 nodes and 65,536 points use flatbush's and kdbush's 32-bit layouts", {
  withr::local_seed(54)
  # An R-tree of 8,200 boxes at node size 2 has more than 16,384 nodes, so
  # its indices are 32-bit; queries still equal a brute-force scan.
  n <- 8200L
  x <- stats::runif(n, 0, 100)
  y <- stats::runif(n, 0, 100)
  e <- geo_extent(x, y, x + 1, y + 1)
  tree <- geo_rtree(e, node_size = 2L)
  q <- geo_extent(40, 40, 45, 45)
  truth <- which(x <= 45 & x + 1 >= 40 & y <= 45 & y + 1 >= 40)
  expect_identical(geo_query_box(tree, q), truth)
  expect_identical(geo_query_box(geo_index_from_raw(geo_index_raw(tree)), q), truth)
  # A k-d tree of 65,536 points stores 32-bit ids.
  m <- 65536L
  px <- stats::runif(m, 0, 100)
  py <- stats::runif(m, 0, 100)
  kd <- geo_kdtree(geo_points(px, py))
  expect_identical(
    geo_query_box(kd, q),
    which(px >= 40 & px <= 45 & py >= 40 & py <= 45)
  )
  expect_identical(
    geo_query_radius(kd, 50, 50, 2),
    which((px - 50)^2 + (py - 50)^2 <= 4)
  )
  # The id width is in the bytes: 8 header bytes, then 4 per id.
  bytes <- geo_index_raw(kd)
  expect_identical(length(bytes), 8L + 4L * m + 16L * m)
})
