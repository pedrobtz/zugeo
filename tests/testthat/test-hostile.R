# Hostile input that design section 9 names and the C error branches it
# reaches (#52): arrays that do not match their schema, malformed WKB inside
# an Arrow column (geo_vctr() checks WKB it is given, but an Arrow producer's
# column arrives unchecked), malformed schemas, and truncated index bytes.

test_that("a chunk that does not match its schema is a layout error", {
  w <- zgo_vctr_new(1:3, list(zuarrow::arrow_array(1:3)), ga_schema("point"))
  for (f in list(format, is.na, geo_box, geo_as_wkb)) {
    expect_error(f(w), "does not match its schema", class = "zugeo_layout_error")
  }
})

test_that("malformed WKB inside an Arrow column is an error in every kernel, never a crash", {
  bad <- zuarrow::arrow_array(list(as.raw(1:3), as.raw(c(1, 1, 0, 0, 0))))
  v <- zgo_vctr_new(1:2, list(bad), zgo_schema(ga_field(zgo_spec("z"), "geoarrow.wkb")))
  kernels <- list(
    geo_box = geo_box, geo_types = geo_types, geo_n_coords = geo_n_coords,
    geo_validate = geo_validate, format = format, geo_as_wkt = geo_as_wkt,
    geo_as_wkb = geo_as_wkb, geo_coords = geo_coords, geo_as_native = geo_as_native,
    geo_hilbert = geo_hilbert, geo_rtree = geo_rtree
  )
  for (name in names(kernels)) {
    expect_error(kernels[[name]](v), class = "zugeo_layout_error", label = name)
  }
  # Nulls are read from the validity bitmap, not the bytes.
  expect_identical(is.na(v), c(FALSE, FALSE))
})

test_that("malformed schemas are layout errors", {
  describe <- function(spec, extension = "geoarrow.point") {
    geo_type_of(zgo_schema(ga_field(spec, extension)))
  }
  g <- function(name) zgo_spec("g", name, nullable = FALSE)
  # Separated coordinates with one field, and with five.
  expect_error(describe(zgo_spec("+s", children = list(g("x")))), class = "zugeo_layout_error")
  expect_error(
    describe(zgo_spec("+s", children = lapply(c("x", "y", "z", "m", "w"), g))),
    class = "zugeo_layout_error"
  )
  # Interleaved coordinates with two children, and of width five.
  expect_error(
    describe(zgo_spec("+w:2", children = list(g("xy"), g("xy")))),
    class = "zugeo_layout_error"
  )
  expect_error(
    describe(zgo_spec("+w:5", children = list(g("xyzmw")))),
    class = "zugeo_layout_error"
  )
  # Coordinates that are neither a struct nor a fixed-size list.
  expect_error(describe(g("x")), class = "zugeo_layout_error")
  # A list with no child.
  expect_error(
    describe(zgo_spec("+l", children = list()), "geoarrow.linestring"),
    class = "zugeo_layout_error"
  )
  # A box that is not a struct.
  expect_error(describe(g("box"), "geoarrow.box"), class = "zugeo_layout_error")
  # A geometrycollection that is not a list, and one whose child is not a
  # union.
  expect_error(describe(ga_coord(), "geoarrow.geometrycollection"), class = "zugeo_layout_error")
  expect_error(
    describe(ga_list(ga_native("point")), "geoarrow.geometrycollection"),
    class = "zugeo_layout_error"
  )
  expect_error(
    describe(zgo_spec("+l", children = list()), "geoarrow.geometrycollection"),
    class = "zugeo_layout_error"
  )
  # A union's geometry collection child (type id 7) that is not a list, and
  # one that is a list with no child.
  u <- ga_union(c(1L, 7L))
  u$children[[2]] <- ga_coord()
  u$children[[2]]$name <- "GeometryCollection"
  expect_error(describe(u, "geoarrow.geometry"), "needs a list of a union",
    class = "zugeo_layout_error"
  )
  u$children[[2]] <- zgo_spec("+l", "GeometryCollection", children = list())
  expect_error(describe(u, "geoarrow.geometry"), "no child", class = "zugeo_layout_error")
  # An extension name longer than any GeoArrow name.
  expect_error(
    describe(zgo_spec("z"), paste0("geoarrow.", strrep("x", 80))),
    "not a GeoArrow 0.2",
    class = "zugeo_layout_error"
  )
  # Dictionary-encoded storage (zgo_view_init()'s first check) cannot be
  # built with zgo_spec(), which has no dictionary: it takes a foreign
  # producer's dictionary-encoded field, so the guard is untested here.
})

test_that("a k-d tree whose bytes are cut short is refused", {
  kd <- geo_index_raw(geo_kdtree(geo_points(1:10, 1:10)))
  expect_error(geo_index_from_raw(kd[-length(kd)]), class = "zugeo_index_error")
  expect_error(geo_index_from_raw(kd[1:7]), class = "zugeo_index_error")
})
