# Design section 6.3's property test: every coordinate round-trips through
# WKT, WKB and both native layouts bit for bit.

test_that("hard doubles round-trip through every encoding exactly", {
  v <- hard_doubles()
  v <- v[is.finite(v)]
  x <- geo_points(v, rev(v), z = -v)
  routes <- list(
    wkt = function(g) geo_vctr(geo_as_wkt(g)),
    wkb = function(g) geo_vctr(geo_as_wkb(g)),
    separated = function(g) geo_as_native(g, "separated"),
    interleaved = function(g) geo_as_native(g, "interleaved")
  )
  for (route in names(routes)) {
    y <- routes[[route]](x)
    coords <- geo_coords(y)
    expect_true(same_bits(coords$x, v), label = route)
    expect_true(same_bits(coords$y, rev(v)), label = route)
    expect_true(same_bits(coords$z, -v), label = route)
  }
  # WKT through WKB through native and back, in one chain.
  chain <- geo_as_native(geo_vctr(geo_as_wkb(geo_vctr(geo_as_wkt(x)))), "interleaved")
  expect_true(same_bits(geo_coords(chain)$x, v))
})

test_that("the shortest digits are what WKT prints", {
  x <- geo_points(c(0.1, 1e-20, 0.01234567890123456, -0), c(1 / 3, 5e-324, 1e21, 1e17))
  expect_identical(
    as.vector(geo_as_wkt(x)),
    c("POINT (0.1 0.3333333333333333)", "POINT (1e-20 5e-324)",
      "POINT (0.01234567890123456 1e+21)", "POINT (-0 100000000000000000)")
  )
})

test_that("every corpus coordinate round-trips through every encoding", {
  natives <- 0L
  for (file in names(corpus_manifest())) {
    g <- zuarrow::arrow_read(corpus_path(file))$geometry
    want <- geo_coords(g)
    for (route in c("wkt", "wkb")) {
      y <- if (route == "wkt") geo_vctr(geo_as_wkt(g)) else geo_vctr(geo_as_wkb(g))
      got <- geo_coords(y)
      expect_identical(got, want, label = paste(file, route))
    }
    native <- tryCatch(geo_as_native(g), zugeo_layout_error = function(e) NULL)
    if (!is.null(native)) {
      natives <- natives + 1L
      expect_identical(geo_coords(native)[c("x", "y")], want[c("x", "y")], label = paste(file, "native"))
      expect_identical(is.na(native), is.na(g), label = paste(file, "native nulls"))
    }
  }
  # 96 of the pinned corpus's 122 files have one native type; the rest mix
  # types or hold collections, which only WKB and WKT carry.
  expect_identical(natives, 96L)
})
