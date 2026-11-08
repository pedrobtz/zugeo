# Stage 4: design section 6.3's errors and the lossy policy, as matrices.

test_that("WKB and WKT lose a non-planar edge type only where there are edges", {
  for (edges in edge_types) {
    for (case in names(edge_cases)) {
      x <- geo_vctr(edge_cases[[case]][[1]], edges = edges)
      lost <- edges != "planar" && edge_cases[[case]][[2]]
      label <- paste(edges, case)
      for (fun in list(geo_as_wkb, geo_as_wkt)) {
        if (lost) {
          err <- expect_error(fun(x), class = "zugeo_edges_error", label = label)
          expect_identical(err$edges, edges, label = label)
          expect_warning(out <- fun(x, lossy = "warn"), class = "zugeo_edges_warning", label = label)
          expect_length(out, length(x))
          expect_silent(fun(x, lossy = "allow"))
        } else {
          expect_silent(out <- fun(x))
          expect_length(out, length(x))
        }
      }
    }
  }
})

test_that("conversions that keep the edge type never complain", {
  for (edges in edge_types[-1]) {
    x <- geo_vctr(c("POLYGON ((0 0, 1 0, 0 1, 0 0))", "MULTIPOLYGON (((0 0, 2 0, 0 2, 0 0)))"),
      edges = edges)
    n <- geo_as_native(x)
    expect_identical(geo_type_of(n)$edges, edges)
    back <- round_trip(data.frame(g = n))$g
    expect_identical(geo_type_of(back)$edges, edges)
    coords <- geo_coords(x)
    expect_identical(attr(coords, "edges"), edges)
    expect_identical(geo_type_of(geo_from_coords(coords, "multipolygon"))$edges, edges)
  }
})

test_that("an invalid lossy policy is an error", {
  x <- geo_vctr("POINT (1 2)")
  expect_error(geo_as_wkb(x, lossy = "maybe"), class = "zugeo_error")
  # No partial matching: "w" is not "warn".
  expect_error(geo_as_wkb(x, lossy = "w"), class = "zugeo_error")
  expect_snapshot(geo_as_wkb(x, lossy = "maybe"), error = TRUE)
})

test_that("every CRS form survives every route, never invented or dropped", {
  for (case in names(crs_cases)) {
    crs <- crs_cases[[case]]
    x <- geo_vctr(c("POINT (1 2)", "LINESTRING (0 0, 1 1)", NA), crs = crs)
    want <- geo_crs(crs)
    routes <- list(
      wkb = geo_vctr(geo_as_wkb(x)),
      wkt = geo_vctr(geo_as_wkt(x)),
      native = geo_as_native(x[2], type = "linestring"),
      arrow = round_trip(data.frame(g = x))$g,
      gathered = round_trip(data.frame(g = rev(x)))$g,
      coords = geo_from_coords(geo_coords(x[2]), "linestring")
    )
    for (route in names(routes)) {
      got <- geo_crs(routes[[route]])
      expect_true(geo_crs_equal(got, want), label = paste(case, route))
      expect_identical(got$type, want$type, label = paste(case, route, "type"))
    }
    # A CRS in, the same CRS as text out, and nothing when there is none.
    expect_identical(is.na(geo_crs_text(x)), is.null(want$value), label = case)
  }
})

test_that("combining columns of different CRS is a CRS error, both ways", {
  a <- geo_vctr("POINT (1 2)", crs = "OGC:CRS84")
  b <- geo_vctr("POINT (1 2)", crs = "EPSG:3857")
  n <- geo_vctr("POINT (1 2)")
  expect_error(c(a, b), class = "zugeo_crs_error")
  expect_error(c(a, n), class = "zugeo_crs_error")
  expect_error(c(n, a), class = "zugeo_crs_error")
  expect_length(c(a, a), 2L)
})

test_that("a null inside a geometry is a layout error at read", {
  inner <- zuarrow::arrow_array(data.frame(x = c(1, NA), y = c(2, 3)))
  schema <- ga_schema("point")
  expect_error(
    zgo_from_array(inner, schema, call = NULL),
    "null inside a geometry",
    class = "zugeo_layout_error"
  )
  clean <- zuarrow::arrow_array(data.frame(x = c(1, 2), y = c(2, 3)))
  expect_length(zgo_from_array(clean, schema, call = NULL), 2L)
})

test_that("reading with zuarrow's lossy policy loses nothing either way", {
  g <- union_vctr()
  for (lossy in c("error", "warn", "allow")) {
    expect_silent(df <- zuarrow::arrow_read(union_path(), lossy = lossy))
    expect_identical(format(df$geom), format(g))
  }
})
