describe_spec <- function(spec) geo_type_of(zgo_schema(spec))

test_that("every native type, dimension, coordinate layout and list width", {
  levels <- c(point = 0L, linestring = 1L, polygon = 2L, multipoint = 1L,
    multilinestring = 2L, multipolygon = 3L)
  for (type in names(levels)) {
    for (dims in c("xy", "xyz", "xym", "xyzm")) {
      for (coord in c("separated", "interleaved")) {
        for (large in c(FALSE, TRUE)) {
          t <- geo_type_of(ga_schema(type, dims, coord, large))
          label <- paste(type, dims, coord, large)
          expect_s3_class(t, "zugeo_type")
          expect_identical(t$extension, paste0("geoarrow.", type), label = label)
          expect_identical(t$encoding, "native", label = label)
          expect_identical(t$geometry_type, type, label = label)
          expect_identical(t$dimensions, dims, label = label)
          expect_identical(t$coord_type, coord, label = label)
          expect_identical(
            t$offsets,
            rep(if (large) "large_list" else "list", levels[[type]]),
            label = label
          )
        }
      }
    }
  }
})

test_that("well-known binary and text in every storage type", {
  for (format in c("z", "Z", "vz")) {
    t <- describe_spec(ga_field(zgo_spec(format), "geoarrow.wkb"))
    expect_identical(t$encoding, "wkb")
    expect_identical(t$storage, format)
    expect_identical(t$geometry_type, "geometry")
    expect_identical(t$dimensions, NA_character_)
  }
  for (format in c("u", "U", "vu")) {
    t <- describe_spec(ga_field(zgo_spec(format), "geoarrow.wkt"))
    expect_identical(t$encoding, "wkt")
    expect_identical(t$storage, format)
  }
  expect_error(
    describe_spec(ga_field(zgo_spec("u"), "geoarrow.wkb")),
    class = "zugeo_layout_error"
  )
  expect_error(
    describe_spec(ga_field(zgo_spec("z"), "geoarrow.wkt")),
    class = "zugeo_layout_error"
  )
})

test_that("geometry unions record their type ids and dimensions", {
  t <- describe_spec(ga_field(ga_union(c(1L, 3L, 6L)), "geoarrow.geometry"))
  expect_identical(t$geometry_type, "geometry")
  expect_identical(t$union_ids, c(1L, 3L, 6L))
  expect_identical(t$dimensions, "xy")
  expect_identical(t$coord_type, "separated")

  mixed <- describe_spec(ga_field(ga_union(c(1L, 11L, 37L)), "geoarrow.geometry"))
  expect_identical(mixed$dimensions, NA_character_)
  expect_identical(mixed$union_ids, c(1L, 11L, 37L))
})

test_that("geometry collections are a list of a union without collections", {
  inner <- ga_union(c(11L, 12L))
  t <- describe_spec(ga_field(ga_list(inner), "geoarrow.geometrycollection"))
  expect_identical(t$geometry_type, "geometrycollection")
  expect_identical(t$dimensions, "xyz")
  expect_identical(t$offsets, "list")

  nested <- ga_union(c(1L, 7L))
  expect_error(
    describe_spec(ga_field(ga_list(nested), "geoarrow.geometrycollection")),
    "type id 7",
    class = "zugeo_layout_error"
  )
  mixed <- ga_union(c(1L, 12L))
  expect_error(
    describe_spec(ga_field(ga_list(mixed), "geoarrow.geometrycollection")),
    "mixes dimensions",
    class = "zugeo_layout_error"
  )
})

test_that("boxes need their fields named as GeoArrow fixes them", {
  box <- function(names) {
    ga_field(
      zgo_spec("+s", children = lapply(names, function(n) zgo_spec("g", n))),
      "geoarrow.box"
    )
  }
  expect_identical(describe_spec(box(c("xmin", "ymin", "xmax", "ymax")))$dimensions, "xy")
  expect_identical(
    describe_spec(box(c("xmin", "ymin", "mmin", "xmax", "ymax", "mmax")))$dimensions,
    "xym"
  )
  expect_identical(
    describe_spec(box(c("xmin", "ymin", "zmin", "mmin", "xmax", "ymax", "zmax", "mmax")))$dimensions,
    "xyzm"
  )
  t <- describe_spec(box(c("xmin", "ymin", "zmin", "xmax", "ymax", "zmax")))
  expect_identical(t$encoding, "box")
  expect_identical(t$geometry_type, "box")
  expect_error(
    describe_spec(box(c("xmin", "xmax", "ymin", "ymax"))),
    class = "zugeo_layout_error"
  )
})

test_that("layouts GeoArrow forbids are layout errors", {
  # Three coordinates whose third is neither z nor m.
  coord <- zgo_spec("+s", children = list(
    zgo_spec("g", "x"), zgo_spec("g", "y"), zgo_spec("g", "w")
  ))
  expect_error(
    describe_spec(ga_field(coord, "geoarrow.point")),
    "'z' or 'm'",
    class = "zugeo_layout_error"
  )
  # Width-three interleaved coordinates with an ambiguous name.
  inter <- zgo_spec("+w:3", children = list(zgo_spec("g", "coords")))
  expect_error(
    describe_spec(ga_field(inter, "geoarrow.point")),
    "'xyz' or 'xym'",
    class = "zugeo_layout_error"
  )
  # Integer coordinates.
  ints <- zgo_spec("+s", children = list(zgo_spec("i", "x"), zgo_spec("i", "y")))
  expect_error(describe_spec(ga_field(ints, "geoarrow.point")), class = "zugeo_layout_error")
  # Too few list levels for a polygon.
  expect_error(
    describe_spec(ga_field(ga_native("linestring"), "geoarrow.polygon")),
    class = "zugeo_layout_error"
  )
  # A child carrying extension metadata.
  child <- ga_coord()
  child$metadata <- c("ARROW:extension:name" = "geoarrow.point")
  expect_error(
    describe_spec(ga_field(ga_list(child), "geoarrow.linestring")),
    "extension metadata",
    class = "zugeo_layout_error"
  )
  # Union type ids GeoArrow does not define, or repeated.
  bad <- ga_union(c(1L, 2L))
  for (ids in c("+ud:1,8", "+ud:1,47", "+ud:1,2,3", "+ud:1,x", "+ud:1,200")) {
    bad$format <- ids
    expect_error(
      describe_spec(ga_field(bad, "geoarrow.geometry")),
      class = "zugeo_layout_error",
      label = ids
    )
  }
  bad$format <- "+ud:1,1"
  expect_error(describe_spec(ga_field(bad, "geoarrow.geometry")), class = "zugeo_layout_error")
  bad$format <- "+us:1,2"
  expect_error(describe_spec(ga_field(bad, "geoarrow.geometry")), "dense union")
  # A union child whose coordinates disagree with its type id.
  wrong <- ga_union(c(11L))
  wrong$children[[1]] <- ga_native("point", "xy")
  expect_error(
    describe_spec(ga_field(wrong, "geoarrow.geometry")),
    "type id 11",
    class = "zugeo_layout_error"
  )
  # A name GeoArrow 0.2 does not define, including near misses.
  for (name in c("geoarrow.wkbx", "geoarrow.points", "geoarrow.")) {
    expect_error(
      describe_spec(ga_field(zgo_spec("z"), name)),
      "not a GeoArrow 0.2 extension name",
      class = "zugeo_layout_error"
    )
  }
})

test_that("a struct has each GeoArrow field described, by name", {
  spec <- zgo_spec("+s", children = list(
    zgo_spec("i", "id"),
    ga_field(ga_native("point"), "geoarrow.point", name = "a"),
    ga_field(zgo_spec("z"), "geoarrow.wkb", name = "b")
  ))
  t <- describe_spec(spec)
  expect_named(t, c("a", "b"))
  expect_identical(t$b$encoding, "wkb")

  none <- zgo_spec("+s", children = list(zgo_spec("i", "id")))
  expect_error(describe_spec(none), "not a GeoArrow field", class = "zugeo_layout_error")
  expect_error(geo_crs(zgo_schema(spec)), "2 GeoArrow fields")
})

test_that("geo_type_of() takes array and stream handles and nothing else", {
  expect_error(geo_type_of(1:3), "handle", class = "zugeo_error")
  stream <- zuarrow::arrow_stream(data.frame(x = 1:2))
  expect_error(geo_type_of(stream), "not a GeoArrow field", class = "zugeo_layout_error")
})

test_that("format() summarises a type", {
  t <- geo_type_of(ga_schema("polygon", "xyz", "interleaved"))
  expect_identical(
    format(t),
    "<geoarrow.polygon native, xyz, interleaved, list/list; crs none; edges planar>"
  )
  expect_output(print(t), "geoarrow.polygon")
})
