test_that("zugeo registers every GeoArrow name and geo_vctr with zuarrow", {
  registry <- zuarrow::arrow_registry()
  ours <- registry[registry$package == "zugeo", ]
  expect_setequal(ours$key, c(zgo_extension_names, "geo_vctr"))
  expect_true(all(ours$exact))
})

test_that("a union column reads as one geo_vctr over its batches", {
  g <- union_vctr()
  expect_s3_class(g, "geo_vctr")
  expect_length(g, 6L)
  expect_length(attr(g, "chunks"), 2L)
  expect_identical(
    format(g),
    c("POINT (1 2)", "LINESTRING (0 0, 1 1)", "POINT Z (3 4 5)", "POINT (5 6)",
      "POINT Z (-1 -2 -3)", "LINESTRING (2 3, 4 5, 6 7)")
  )
  expect_identical(geo_type_of(g)$union_ids, c(1L, 2L, 11L))
})

test_that("subsetting and reordering move positions, never buffers", {
  g <- union_vctr()
  chunks <- attr(g, "chunks")
  r <- rev(g)
  expect_identical(format(r), rev(format(g)))
  expect_identical(attr(r, "chunks"), chunks)
  expect_identical(format(g[c(TRUE, FALSE)]), format(g)[c(1, 3, 5)])
  expect_identical(format(g[[2]]), "LINESTRING (0 0, 1 1)")
  expect_identical(format(rep(g[1], 3)), rep("POINT (1 2)", 3))
  short <- g
  length(short) <- 2L
  expect_length(short, 2L)
  long <- g[1]
  length(long) <- 3L
  expect_identical(is.na(long), c(FALSE, TRUE, TRUE))
  expect_error(g[1] <- g[2], class = "zugeo_error")
  expect_error(g[[1]] <- g[2], class = "zugeo_error")
})

test_that("gathered rows write and read back, nulls and unions included", {
  g <- union_vctr()
  picked <- g[c(6, 3, NA, 1)]
  back <- round_trip(data.frame(geom = picked))$geom
  expect_identical(format(back), format(picked))
  expect_identical(is.na(back), c(FALSE, FALSE, TRUE, FALSE))
  expect_identical(geo_type_of(back)$union_ids, c(1L, 2L, 11L))
})

test_that("an untouched vector exports its own chunk", {
  chunk <- attr(union_vctr(), "chunks")[[1]]
  expect_identical(zgo_to_array(geo_vctr(chunk)), chunk)
  # Any other positions gather a new array.
  expect_false(identical(zgo_to_array(geo_vctr(chunk)[2:1]), chunk))
})

test_that("c() appends the chunks of vectors of one column", {
  g <- union_vctr()
  both <- c(g, NULL, g[2:1])
  expect_length(both, 8L)
  expect_identical(format(both), c(format(g), format(g)[2:1]))
  expect_length(attr(both, "chunks"), 4L)
  expect_error(c(g, 1), "Only geo_vctr", class = "zugeo_error")
})

test_that("c() refuses another CRS, other edges or another layout", {
  g <- union_vctr()
  schema <- attr(g, "schema")
  spec <- ga_field(ga_union(c(1L, 2L, 11L)), "geoarrow.geometry")
  spec$children[[1]]$name <- "Point"
  with_meta <- function(metadata) {
    s <- spec
    s$metadata[["ARROW:extension:metadata"]] <- metadata
    zgo_vctr_new(seq_along(g), attr(g, "chunks"), zgo_schema(s))
  }
  expect_error(c(g, with_meta('{"crs": "OGC:CRS84"}')), class = "zugeo_crs_error")
  expect_error(c(g, with_meta('{"edges": "spherical"}')), class = "zugeo_crs_error")
  point <- zgo_vctr_new(1L, attr(g, "chunks")[1], ga_schema("point"))
  expect_error(c(g, point), "convert one", class = "zugeo_layout_error")
})

test_that("geo_vctr() takes an array handle and nothing else", {
  g <- union_vctr()
  a <- attr(g, "chunks")[[2]]
  v <- geo_vctr(a)
  expect_identical(format(v), format(g)[5:6])
  expect_identical(geo_vctr(v), v)
  expect_true(is_geo_vctr(v))
  expect_false(is_geo_vctr(1))
  expect_error(geo_vctr(1), "array handle", class = "zugeo_error")
  expect_identical(geo_crs(v), geo_crs(NULL))
})

test_that("format(), print() and as.data.frame()", {
  g <- union_vctr()
  expect_identical(format(g[6], max_bytes = 10), "LINESTRING")
  expect_identical(format(g[c(6, 1)], max_bytes = 10), c("LINESTRING", "POINT (1 2"))
  expect_output(print(g), "<geo_vctr\\[6\\] geoarrow.geometry")
  expect_output(print(g), "\\[6\\] LINESTRING")
  expect_identical(as.character(g[c(1, NA)]), c("POINT (1 2)", NA))
  expect_identical(format(g[c(1, NA)]), c("POINT (1 2)", "<null>"))
  df <- as.data.frame(g)
  expect_identical(nrow(df), 6L)
  expect_s3_class(df[[1]], "geo_vctr")
  expect_output(print(g[0]), "<geo_vctr\\[0\\]")
})
