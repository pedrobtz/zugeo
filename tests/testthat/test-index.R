test_that("R-tree box queries equal a brute-force scan", {
  for (n in c(1L, 7L, 16L, 17L, 300L, 5000L)) {
    e <- random_boxes(n, seed = n)
    for (node_size in c(2L, 4L, 16L)) {
      tree <- geo_rtree(e, node_size = node_size)
      for (i in 1:5) {
        q <- random_boxes(1, seed = 1000 + i, size = 20)
        expect_identical(geo_query_box(tree, q), brute_box(e, q), label = paste(n, node_size, i))
      }
    }
  }
  # Several queries at once: a data frame.
  e <- random_boxes(500)
  q <- random_boxes(3, seed = 9, size = 15)
  got <- geo_query_box(geo_rtree(e), q)
  want <- do.call(rbind, lapply(1:3, function(i) data.frame(query = rep(i, length(brute_box(e, q[i]))), row = brute_box(e, q[i]))))
  expect_identical(unname(as.matrix(got)), unname(as.matrix(want)))
})

test_that("nearest neighbours by box distance equal a brute-force ranking", {
  e <- random_boxes(2000, seed = 3)
  tree <- geo_rtree(e)
  for (p in list(c(50, 50), c(-10, 50), c(101, 101))) {
    got <- geo_query_nearest(tree, p[1], p[2], k = 10)
    d <- brute_box_distance(e, p[1], p[2])
    expect_equal(got$distance, sort(d)[1:10])
    expect_equal(d[got$row], got$distance)
  }
  limited <- geo_query_nearest(tree, 50, 50, k = 100, max_distance = 1)
  expect_true(all(limited$distance <= 1))
  expect_identical(nrow(limited), sum(brute_box_distance(e, 50, 50) <= 1))
  two <- geo_query_nearest(tree, c(0, 100), c(0, 100), k = 3)
  expect_identical(two$query, rep(1:2, each = 3))
  expect_error(geo_query_nearest(tree, 0, 0, k = 0), class = "zugeo_error")
})

test_that("both joins equal a brute-force scan, and each other", {
  a <- random_boxes(800, seed = 4)
  b <- random_boxes(300, seed = 5, size = 4)
  want <- do.call(rbind, lapply(seq_along(b), function(j) {
    hit <- brute_box(a, b[j])
    if (length(hit)) data.frame(x = hit, y = j)
  }))
  want <- want[order(want$x, want$y), ]
  rownames(want) <- NULL
  tree <- geo_rtree(a, node_size = 8)
  expect_identical(geo_join_box(tree, b), want)
  for (node_size in c(2L, 4L, 16L)) {
    expect_identical(geo_join_box(tree, geo_rtree(b, node_size = node_size)), want)
  }
  # A geo_vctr joins through its boxes.
  polys <- geo_vctr(sprintf("POLYGON ((%.17g %.17g, %.17g %.17g, %.17g %.17g, %.17g %.17g))",
    b$xmin, b$ymin, b$xmax, b$ymin, b$xmax, b$ymax, b$xmin, b$ymin))
  expect_identical(geo_join_box(tree, polys), want)
})

test_that("k-d trees answer box and radius queries like a scan", {
  withr::with_seed(6, {
    x <- runif(3000, 0, 100)
    y <- runif(3000, 0, 100)
  })
  pts <- geo_points(x, y)
  for (node_size in c(2L, 16L, 64L)) {
    kd <- geo_kdtree(pts, node_size = node_size)
    expect_identical(geo_query_radius(kd, 40, 60, 5), which((x - 40)^2 + (y - 60)^2 <= 25))
    expect_identical(geo_query_box(kd, geo_extent(10, 20, 30, 25)),
      which(x >= 10 & x <= 30 & y >= 20 & y <= 25))
  }
  several <- geo_query_radius(geo_kdtree(pts), c(10, 90), c(10, 90), 4)
  expect_named(several, c("query", "row"))
  expect_error(geo_kdtree(geo_vctr("LINESTRING (0 0, 1 1)")), "points", class = "zugeo_index_error")
  expect_error(geo_query_radius(geo_rtree(pts), 0, 0, 1), "k-d tree")
  expect_error(geo_query_nearest(geo_kdtree(pts), 0, 0), "R-tree")
})

test_that("nulls and empties are left out; rows refer to the indexed vector", {
  x <- geo_vctr(c(NA, "POINT (1 1)", "POINT EMPTY", "POINT (5 5)", "LINESTRING (0 0, 2 2)"))
  tree <- geo_rtree(x)
  expect_length(tree$rows, 3L)
  expect_identical(geo_query_box(tree, geo_extent(0, 0, 1.5, 1.5)), c(2L, 5L))
  kd <- geo_kdtree(x[1:4])
  expect_identical(geo_query_radius(kd, 5, 5, 0.1), 4L)
  expect_error(geo_rtree(geo_vctr(c(NA, "POINT EMPTY"))), class = "zugeo_index_error")
  expect_output(print(tree), "<zugeo_index rtree: 3 items of 5")
})

test_that("indexes persist as their bytes and read back identically", {
  e <- random_boxes(1000, seed = 7)
  tree <- geo_rtree(e)
  bytes <- geo_index_raw(tree)
  expect_type(bytes, "raw")
  expect_identical(bytes[1], as.raw(0xfb))
  back <- geo_index_from_raw(bytes)
  q <- random_boxes(1, seed = 8, size = 30)
  expect_identical(geo_query_box(back, q), geo_query_box(tree, q))
  path <- withr::local_tempfile()
  writeBin(bytes, path)
  expect_identical(readBin(path, "raw", length(bytes) + 1L), bytes)
  kd <- geo_kdtree(geo_points(e$xmin, e$ymin))
  kd_bytes <- geo_index_raw(kd)
  expect_identical(kd_bytes[1], as.raw(0xdb))
  expect_identical(geo_query_radius(geo_index_from_raw(kd_bytes), 50, 50, 5),
    geo_query_radius(kd, 50, 50, 5))
})

test_that("hostile bytes are an index error, never a crash", {
  bytes <- geo_index_raw(geo_rtree(random_boxes(400, seed = 10)))
  kd_bytes <- geo_index_raw(geo_kdtree(geo_points(1:100, 1:100)))
  expect_error(geo_index_from_raw(bytes[1:7]), class = "zugeo_index_error")
  expect_error(geo_index_from_raw(bytes[-length(bytes)]), class = "zugeo_index_error")
  expect_error(geo_index_from_raw(c(bytes, as.raw(0))), class = "zugeo_index_error")
  wrong <- bytes
  wrong[1] <- as.raw(0)
  expect_error(geo_index_from_raw(wrong), "neither", class = "zugeo_index_error")
  wrong <- bytes
  wrong[2] <- as.raw(0x27)
  expect_error(geo_index_from_raw(wrong), "version", class = "zugeo_index_error")
  wrong <- kd_bytes
  wrong[2] <- as.raw(0x17)
  expect_error(geo_index_from_raw(wrong), "array type", class = "zugeo_index_error")
  wrong <- bytes
  wrong[5:8] <- as.raw(c(255, 255, 255, 255))
  expect_error(geo_index_from_raw(wrong), class = "zugeo_index_error")
  expect_error(geo_index_from_raw(1:10), class = "zugeo_index_error")
  # Flipped bytes in the boxes and indices: a result or an index error.
  q <- geo_extent(0, 0, 100, 100)
  queried <- 0L
  withr::with_seed(11, {
    for (i in 1:300) {
      flipped <- bytes
      at <- sample(9:length(bytes), 4)
      flipped[at] <- as.raw(sample(0:255, 4))
      tree <- tryCatch(geo_index_from_raw(flipped), zugeo_index_error = function(e) NULL)
      if (is.null(tree)) next
      queried <- queried + 1L
      res <- tryCatch(geo_query_box(tree, q), zugeo_index_error = function(e) "refused")
      expect_true(is.character(res) || all(res >= 1L & res <= 400L))
      res <- tryCatch(geo_query_nearest(tree, 50, 50, k = 3), zugeo_index_error = function(e) "refused")
      expect_true(is.character(res) || is.data.frame(res))
      res <- tryCatch(geo_join_box(tree, tree), zugeo_index_error = function(e) "refused")
      expect_true(is.character(res) || is.data.frame(res))
    }
    for (i in 1:300) {
      flipped <- kd_bytes
      at <- sample(9:length(kd_bytes), 4)
      flipped[at] <- as.raw(sample(0:255, 4))
      kd <- geo_index_from_raw(flipped)
      res <- tryCatch(geo_query_radius(kd, 50, 50, 20), zugeo_index_error = function(e) "refused")
      expect_true(is.character(res) || all(res >= 1L & res <= 100L))
    }
  })
  # Most flips leave a parseable tree, so the queries above really ran.
  expect_gt(queried, 100L)
})

test_that("arguments are checked", {
  e <- random_boxes(10)
  expect_error(geo_rtree(e, node_size = 1), "node_size")
  expect_error(geo_rtree(e, node_size = 70000), "node_size")
  expect_error(geo_query_box(1, e), "zugeo_index")
  expect_error(geo_query_box(geo_rtree(e), 1), "geo_extent")
  crs <- geo_rtree(geo_extent(0, 0, 1, 1, crs = "OGC:CRS84"))
  expect_error(geo_query_box(crs, geo_extent(0, 0, 1, 1, crs = "EPSG:3857")), class = "zugeo_crs_error")
  expect_error(geo_rtree(geo_extent(170, 0, -170, 1)), class = "zugeo_edges_error")
  expect_error(geo_rtree(geo_vctr("LINESTRING (0 0, 1 1)", edges = "spherical")), class = "zugeo_edges_error")
})

test_that("geometries with a non-finite box are left out of both indexes", {
  withr::local_seed(30)
  n <- 5000L
  x <- stats::runif(n)
  y <- stats::runif(n)
  y[sample(n, 2000L)] <- NaN
  x[c(1L, 2L)] <- c(Inf, -Inf)
  p <- geo_points(x, y)
  q <- geo_extent(0, 0, 0.5, 0.5)
  truth <- which(is.finite(x) & is.finite(y) & x >= 0 & x <= 0.5 & y >= 0 & y <= 0.5)
  expect_identical(geo_query_box(geo_kdtree(p, node_size = 2), q), truth)
  expect_identical(geo_query_box(geo_rtree(p, node_size = 2), q), truth)
  expect_identical(geo_query_box(geo_rtree(p), q), truth)
  expect_error(geo_rtree(geo_points(NaN, 1)), class = "zugeo_index_error")
})
