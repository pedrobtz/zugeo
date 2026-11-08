# GeoParquet through qio (design sections 6.9 and 6.11, Stage 7).

test_that("every case round-trips exactly, CRS and edges included", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)
  cases <- parquet_cases()
  for (name in names(cases)) {
    x <- cases[[name]]$x
    sort <- cases[[name]]$args$sort
    if (is.null(sort) || sort == "hilbert") {
      x <- x[geo_sort(x$geometry, lossy = "allow"), ]
    }
    back <- geo_read_parquet(paths[[name]])
    expect_identical(names(back), names(x), label = name)
    expect_identical(
      geo_as_wkt(back$geometry, lossy = "allow"),
      geo_as_wkt(x$geometry, lossy = "allow"),
      label = name
    )
    expect_true(
      geo_crs_equal(back$geometry, x$geometry),
      label = paste(name, "crs")
    )
    expect_identical(
      geo_type_of(back$geometry)$edges,
      geo_type_of(x$geometry)$edges,
      label = paste(name, "edges")
    )
    other <- setdiff(names(x), "geometry")
    expect_equal(back[other], `rownames<-`(x[other], NULL), label = name)
  }
})

test_that("GeoParquet 2.0 writes native types, a geo key and Hilbert order", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)

  f <- parquet_footer(paths[["points"]])
  geom <- f$schema[f$schema$path == "geometry", ]
  expect_identical(geom$logical_type, "GEOMETRY")
  expect_identical(geom$logical_details, "crs=OGC:CRS84")
  expect_identical(f$geo$version, "2.0.0")
  expect_identical(f$geo$primary_column, "geometry")
  meta <- f$geo$columns$geometry
  expect_identical(meta$encoding, "WKB")
  expect_identical(meta$geometry_types, list("Point"))
  expect_false("crs" %in% names(meta))
  expect_equal(unlist(meta$bbox), c(-73.429673, 2, 1, 45.008308))

  f <- parquet_footer(paths[["mixed_z"]])
  meta <- f$geo$columns$geometry
  expect_identical(
    unlist(meta$geometry_types),
    c("LineString Z", "Polygon Z", "MultiLineString Z", "MultiPolygon Z")
  )
  expect_length(meta$bbox, 6L)
  expect_identical(
    meta$crs,
    zujson::json_parse(crs84_projjson, simplify = FALSE)
  )
  expect_identical(
    f$schema$logical_details[f$schema$path == "geometry"],
    "crs=projjson:projjson_crs_geometry"
  )
  expect_identical(
    f$kv$value[f$kv$key == "projjson_crs_geometry"],
    crs84_projjson
  )

  f <- parquet_footer(paths[["no_crs"]])
  expect_true("crs" %in% names(f$geo$columns$geometry))
  expect_null(f$geo$columns$geometry$crs)
  expect_identical(
    f$schema$logical_details[f$schema$path == "geometry"],
    "crs=srid:0"
  )

  f <- parquet_footer(paths[["spherical"]])
  expect_identical(
    f$schema$logical_type[f$schema$path == "geometry"],
    "GEOGRAPHY"
  )
  expect_identical(
    f$schema$logical_details[f$schema$path == "geometry"],
    "crs=OGC:CRS84, algorithm=SPHERICAL"
  )
  expect_identical(f$geo$columns$geometry$edges, "spherical")
  expect_null(f$geo$columns$geometry$bbox)

  many <- geo_read_parquet(paths[["many"]])$geometry
  expect_identical(geo_sort(many), seq_along(many))
  expect_identical(nrow(geo_parquet_info(paths[["many"]])$row_groups), 10L)
})

test_that("a CRS given by a code goes in the Parquet type only", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)
  f <- parquet_footer(paths[["code_crs"]])
  expect_null(f$geo)
  expect_identical(
    f$schema$logical_details[f$schema$path == "geometry"],
    "crs=EPSG:3857"
  )
  x <- parquet_cases()$code_crs$x
  expect_error(
    geo_write_parquet(x, file.path(dir, "v11.parquet"), version = "1.1"),
    class = "zugeo_crs_error"
  )
  long <- x
  long$geometry <- geo_vctr(
    c("POINT (0 0)", "POINT (1 1)"),
    crs = paste0("PROJCRS[\"", strrep("x", 200), "\"]")
  )
  expect_error(
    geo_write_parquet(long, file.path(dir, "long.parquet")),
    class = "zugeo_crs_error"
  )
})

test_that("geo_write_parquet() takes a geo_vctr and refuses other input", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  geo_write_parquet(geo_points(1:2, 3:4, crs = "OGC:CRS84"), path)
  back <- geo_read_parquet(path)
  expect_named(back, "geometry")
  expect_identical(geo_coords(back$geometry)$y, c(3, 4))
  expect_error(geo_write_parquet(list(1), path), class = "zugeo_error")
  expect_error(geo_write_parquet(data.frame(a = 1), path), class = "zugeo_error")
})

test_that("two geometry columns each keep their CRS, types and box", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  long <- zgo_crs_new(list(type = "GeographicCRS", name = strrep("n", 200)), "projjson")
  x <- data.frame(id = 1:3)
  x$a <- geo_vctr(c(NA, NA, NA), crs = "OGC:CRS84")
  x$b <- geo_points(c(5, 1, 3), c(5, 1, 3), crs = long)
  geo_write_parquet(x, path, sort = "none")
  f <- parquet_footer(path)
  # The first geometry column is primary, even when it is all null.
  expect_identical(f$geo$primary_column, "a")
  expect_identical(f$geo$columns$a$geometry_types, list())
  expect_null(f$geo$columns$a$bbox)
  expect_equal(unlist(f$geo$columns$b$bbox), c(1, 1, 5, 5))
  expect_identical(
    f$schema$logical_details[f$schema$path == "b"], "crs=projjson:projjson_crs_b"
  )
  back <- geo_read_parquet(path)
  expect_true(all(is.na(back$a)))
  expect_true(geo_crs_equal(back$b, x$b))
  expect_identical(geo_crs(back$a)$value, "OGC:CRS84")
  expect_false(any(geo_validate_parquet(path)$severity == "error"))
})

test_that("geo_read_parquet() checks columns and bbox", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  geo_write_parquet(geo_points(1:2, 3:4), path)
  expect_error(geo_read_parquet(path, columns = 1), class = "zugeo_error")
  expect_error(geo_read_parquet(path, columns = NA_character_), class = "zugeo_error")
  expect_error(
    geo_read_parquet(path, bbox = geo_extent(c(0, 1), 0, 2, 2)),
    class = "zugeo_error"
  )
  expect_error(geo_read_parquet(path, bbox = c(0, 0, 1)), class = "zugeo_error")
})

test_that("GeoParquet 1.1 writes plain binary and refuses other edges", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)
  f <- parquet_footer(paths[["points_1.1"]])
  expect_true(is.na(f$schema$logical_type[f$schema$path == "geometry"]))
  expect_identical(f$geo$version, "1.1.0")
  x <- data.frame(id = 1)
  x$geometry <- geo_vctr("LINESTRING (0 0, 1 1)", edges = "karney")
  expect_error(
    geo_write_parquet(x, file.path(dir, "k.parquet"), version = "1.1"),
    class = "zugeo_edges_error"
  )
  geo_write_parquet(x, path <- file.path(dir, "k2.parquet"))
  f <- parquet_footer(path)
  expect_identical(
    f$schema$logical_details[f$schema$path == "geometry"],
    "crs=srid:0, algorithm=KARNEY"
  )
  expect_identical(geo_type_of(geo_read_parquet(path)$geometry)$edges, "karney")
})

test_that("bbox skips row groups and filters rows", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)
  all <- geo_read_parquet(paths[["many"]])
  box <- zgo_extent_parts(geo_box(all$geometry))
  query <- c(-20, -10, 30, 25)
  want <- all[
    box$xmin >= query[1] &
      box$xmax <= query[3] &
      box$ymin >= query[2] &
      box$ymax <= query[4],
  ]
  rownames(want) <- NULL
  got <- geo_read_parquet(paths[["many"]], bbox = query)
  expect_identical(got$id, want$id)
  expect_identical(geo_as_wkt(got$geometry), geo_as_wkt(want$geometry))
  extent <- geo_extent(-20, -10, 30, 25, crs = "OGC:CRS84")
  expect_identical(geo_read_parquet(paths[["many"]], bbox = extent)$id, want$id)
  expect_error(
    geo_read_parquet(
      paths[["many"]],
      bbox = geo_extent(0, 0, 1, 1, crs = "EPSG:3857")
    ),
    class = "zugeo_crs_error"
  )
  none <- geo_read_parquet(paths[["many"]], bbox = c(500, 500, 600, 600))
  expect_identical(nrow(none), 0L)
  expect_s3_class(none$geometry, "geo_vctr")
  expect_identical(names(none), names(all))
  sub <- geo_read_parquet(paths[["many"]], bbox = query, columns = "id")
  expect_identical(names(sub), "id")
  expect_identical(sub$id, want$id)
  expect_error(
    geo_read_parquet(paths[["many"]], bbox = c(1, 1, 0, 0)),
    class = "zugeo_error"
  )
})

test_that("bbox reads only the row groups whose statistics meet it", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  path <- write_parquet_cases(dir)[["many"]]
  boxes <- as.data.frame(geo_parquet_info(path)$columns$geometry$row_group_bbox)
  query <- c(-20, -10, 30, 25)
  meet <- which(boxes$xmin <= query[3] & boxes$xmax >= query[1] &
    boxes$ymin <= query[4] & boxes$ymax >= query[2])
  read <- list()
  collect <- qio::collect
  local_mocked_bindings(
    collect = function(x, ...) {
      read <<- c(read, list(list(...)$row_groups))
      collect(x, ...)
    },
    .package = "qio"
  )
  geo_read_parquet(path, bbox = query)
  expect_length(read, 1L)
  expect_identical(read[[1L]], meet)
  # The point of the statistics: fewer groups than the file has.
  expect_lt(length(meet), nrow(boxes))
  expect_gt(length(meet), 0L)
  # Without bbox, every group.
  read <- list()
  geo_read_parquet(path)
  expect_null(read[[1L]])
})

test_that("geo_parquet_info() reads the footer", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)
  info <- geo_parquet_info(paths[["many"]])
  expect_s3_class(info, "zugeo_parquet_info")
  expect_identical(info$rows, 1000)
  expect_identical(info$version, "2.0.0")
  expect_identical(info$primary_column, "geometry")
  col <- info$columns$geometry
  expect_identical(col$logical_type, "GEOMETRY")
  expect_identical(col$geometry_types, "Point")
  expect_s3_class(col$row_group_bbox, "geo_extent")
  expect_length(col$row_group_bbox, 10L)
  all <- geo_read_parquet(paths[["many"]])
  first <- geo_box_all(all$geometry[1:100])
  expect_identical(
    as.data.frame(col$row_group_bbox[1]),
    as.data.frame(first)[c("xmin", "ymin", "xmax", "ymax")]
  )
  expect_snapshot(print(geo_parquet_info(paths[["mixed_z"]])))
  code <- geo_parquet_info(paths[["code_crs"]])
  expect_true(is.na(code$version))
  expect_identical(code$columns$geometry$crs$value, "EPSG:3857")
})

test_that("a covering column's statistics give the row-group boxes and prune", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  x <- as.double(0:39)
  df <- data.frame(id = 0:39, bxmin = x, bymin = x, bxmax = x + 0.5, bymax = x + 0.5)
  df$geometry <- wkb_list(sprintf("POINT (%.1f %.1f)", x + 0.25, x + 0.25))
  # Plain binary, as GeoParquet 1.1 writes it: no native statistics, so the
  # covering is the only source of boxes. The paths have one segment here;
  # a struct column's are two, joined the same way.
  geo <- zujson::json_write(list(
    version = "1.1.0", primary_column = "geometry",
    columns = list(geometry = list(
      encoding = "WKB", geometry_types = list("Point"),
      covering = list(bbox = list(
        xmin = list("bxmin"), ymin = list("bymin"),
        xmax = list("bxmax"), ymax = list("bymax")
      ))
    ))
  ))
  qio::write_parquet(df, path, row_group_size = 10, metadata = c(geo = geo))
  boxes <- as.data.frame(geo_parquet_info(path)$columns$geometry$row_group_bbox)
  expect_identical(boxes$xmin, c(0, 10, 20, 30))
  expect_identical(boxes$ymin, c(0, 10, 20, 30))
  expect_identical(boxes$xmax, c(9.5, 19.5, 29.5, 39.5))
  expect_identical(boxes$ymax, c(9.5, 19.5, 29.5, 39.5))
  read <- list()
  collect <- qio::collect
  local_mocked_bindings(
    collect = function(x, ...) {
      read <<- c(read, list(list(...)$row_groups))
      collect(x, ...)
    },
    .package = "qio"
  )
  got <- geo_read_parquet(path, bbox = c(12, 12, 13, 13))
  expect_identical(read[[1L]], 2L)
  expect_identical(got$id, 12L)
})

test_that("the geo key and the native type must agree", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  df <- data.frame(id = 1:2)
  df$geometry <- wkb_list(c("POINT (1 2)", "POINT (3 4)"))
  key <- function(...) {
    zujson::json_write(list(
      version = "2.0.0",
      primary_column = "geometry",
      columns = list(
        geometry = c(list(encoding = "WKB", geometry_types = list()), list(...))
      )
    ))
  }
  p <- write_raw_parquet(
    df,
    file.path(dir, "crs.parquet"),
    schema = qio::parquet_schema(
      geometry = list("GEOMETRY", crs = "EPSG:3857")
    ),
    geo = key(crs = zujson::json_parse(crs84_projjson, simplify = FALSE))
  )
  err <- expect_error(geo_read_parquet(p), class = "zugeo_parquet_error")
  expect_identical(err$column, "geometry")
  v <- geo_validate_parquet(p, metadata_only = TRUE)
  expect_true("crs_mismatch" %in% v$issue)

  p <- write_raw_parquet(
    df,
    file.path(dir, "null.parquet"),
    schema = qio::parquet_schema(
      geometry = list("GEOMETRY", crs = "OGC:CRS84")
    ),
    geo = key(crs = NULL)
  )
  expect_error(geo_read_parquet(p), class = "zugeo_parquet_error")

  p <- write_raw_parquet(
    df,
    file.path(dir, "edges.parquet"),
    schema = qio::parquet_schema(geometry = list("GEOGRAPHY")),
    geo = key()
  )
  expect_error(geo_read_parquet(p), class = "zugeo_parquet_error")
  expect_true("edges_mismatch" %in% geo_validate_parquet(p)$issue)

  # The same CRS as a code and as PROJJSON agree, and the PROJJSON is kept.
  p <- write_raw_parquet(
    df,
    file.path(dir, "same.parquet"),
    schema = qio::parquet_schema(
      geometry = list("GEOMETRY", crs = "EPSG:4326")
    ),
    geo = key(crs = zujson::json_parse(crs84_projjson, simplify = FALSE))
  )
  expect_identical(geo_crs(geo_read_parquet(p)$geometry)$type, "projjson")

  p <- write_raw_parquet(
    df,
    file.path(dir, "key.parquet"),
    schema = qio::parquet_schema(
      geometry = list("GEOMETRY", crs = "projjson:nowhere")
    )
  )
  expect_error(geo_read_parquet(p), class = "zugeo_metadata_error")
  expect_true("crs_key_missing" %in% geo_validate_parquet(p)$issue)
})

test_that("a GeoArrow-encoded column is refused, not misread", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  df <- data.frame(id = 1:2)
  df$geometry <- wkb_list(c("POINT (1 2)", "POINT (3 4)"))
  for (encoding in c("point", "multipolygon")) {
    geo <- zujson::json_write(list(
      version = "1.1.0", primary_column = "geometry",
      columns = list(geometry = list(encoding = encoding, geometry_types = list()))
    ))
    p <- write_raw_parquet(df, file.path(dir, paste0(encoding, ".parquet")), geo = geo)
    err <- expect_error(geo_read_parquet(p), class = "zugeo_parquet_error")
    expect_identical(err$column, "geometry")
    expect_error(geo_read_parquet(p, bbox = c(0, 0, 5, 5)), class = "zugeo_parquet_error")
    expect_identical(geo_parquet_info(p)$columns$geometry$encoding, encoding)
    # The other columns still read.
    expect_identical(geo_read_parquet(p, columns = "id")$id, 1:2)
  }
})

test_that("malformed files are errors, not guesses", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  df <- data.frame(id = 1:2)
  p <- write_raw_parquet(df, file.path(dir, "plain.parquet"))
  expect_error(geo_read_parquet(p), class = "zugeo_parquet_error")
  p <- write_raw_parquet(df, file.path(dir, "json.parquet"), geo = "{not json")
  expect_error(geo_read_parquet(p), class = "zugeo_metadata_error")
  expect_identical(geo_validate_parquet(p)$issue[[1L]], "geo_key_invalid")
  df$geometry <- wkb_list(c("POINT (1 2)", "POINT (3 4)"))
  geo <- zujson::json_write(list(
    version = "1.0.0",
    primary_column = "geometry",
    columns = list(geometry = list(encoding = "WKT", geometry_types = list()))
  ))
  p <- write_raw_parquet(df, file.path(dir, "wkt.parquet"), geo = geo)
  expect_error(geo_read_parquet(p), class = "zugeo_metadata_error")
  expect_error(geo_read_parquet(1), class = "zugeo_error")
  expect_error(
    geo_write_parquet(data.frame(a = 1), tempfile()),
    class = "zugeo_error"
  )
})

test_that("CRS and metadata reconciliation covers every form", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  df <- data.frame(id = 1:2)
  df$geometry <- wkb_list(c("POINT (1 2)", "POINT (3 4)"))
  key <- function(...) {
    zujson::json_write(list(
      version = "2.0.0", primary_column = "geometry",
      columns = list(geometry = c(list(encoding = "WKB", geometry_types = list()), list(...)))
    ))
  }
  # A projjson: footer key that does not hold PROJJSON.
  p <- write_raw_parquet(df, file.path(dir, "key.parquet"),
    schema = qio::parquet_schema(geometry = list("GEOMETRY", crs = "projjson:k")),
    extra = c(k = "EPSG:4326")
  )
  err <- expect_error(geo_read_parquet(p), class = "zugeo_metadata_error")
  expect_identical(err$issue, "crs_key_missing")
  # A geo key that is JSON but not an object, or has no columns.
  for (geo in c("[1, 2]", '{"version": "1.1.0"}')) {
    p <- write_raw_parquet(df, file.path(dir, "geo.parquet"), geo = geo)
    expect_error(geo_read_parquet(p), class = "zugeo_metadata_error", label = geo)
  }
  # Unknown edges in the geo key.
  p <- write_raw_parquet(df, file.path(dir, "edges.parquet"), geo = key(edges = "curvy"))
  expect_error(geo_read_parquet(p), class = "zugeo_metadata_error")
  # PROJJSON without an id beside a code: zugeo cannot tell without PROJ,
  # so the two are taken on trust and the geo key's PROJJSON is kept.
  anonymous <- list(type = "GeographicCRS", name = "Somewhere")
  p <- write_raw_parquet(df, file.path(dir, "trust.parquet"),
    schema = qio::parquet_schema(geometry = list("GEOMETRY", crs = "EPSG:4326")),
    geo = key(crs = anonymous)
  )
  crs <- geo_crs(geo_read_parquet(p)$geometry)
  expect_identical(crs$type, "projjson")
  expect_identical(crs$value$name, "Somewhere")
})

test_that("an srid CRS goes through the Parquet type both ways", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  x <- geo_points(1:2, 3:4, crs = geo_crs("5070", crs_type = "srid"))
  geo_write_parquet(x, path, sort = "none")
  f <- parquet_footer(path)
  expect_identical(f$schema$logical_details[f$schema$path == "geometry"], "crs=srid:5070")
  expect_null(f$geo)
  back <- geo_crs(geo_read_parquet(path)$geometry)
  expect_identical(back$type, "srid")
  expect_identical(back$value, "5070")
})

test_that("geo_validate_parquet() passes zugeo's own files", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)
  for (name in setdiff(names(paths), "code_crs")) {
    v <- geo_validate_parquet(paths[[name]])
    expect_identical(v$issue[v$severity == "error"], character(), label = name)
  }
  v <- geo_validate_parquet(paths[["code_crs"]])
  expect_identical(v$issue, "geo_key_missing")
  expect_named(
    v,
    c("column", "row_group", "row", "issue", "severity", "message")
  )
})

test_that("geo_validate_parquet() reports a malformed geo key's structure", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  df <- data.frame(id = 1:2)
  df$geometry <- wkb_list(c("POINT (1 2)", "POINT (3 4)"))
  issues <- function(geo, ...) {
    p <- write_raw_parquet(df, file.path(dir, "f.parquet"), geo = geo, ...)
    geo_validate_parquet(p, metadata_only = TRUE)$issue
  }
  json <- function(...) as.character(zujson::json_write(list(...)))
  entry <- list(encoding = "WKB", geometry_types = list())
  expect_true("columns_invalid" %in% issues(json(
    version = "1.1.0", primary_column = "geometry", columns = structure(list(), names = character())
  )))
  expect_true("columns_invalid" %in% issues(json(
    version = "1.1.0", primary_column = "geometry", columns = list(geometry = 1)
  )))
  expect_true("primary_column_not_in_columns" %in% issues(json(
    version = "1.1.0", primary_column = "nope", columns = list(geometry = entry)
  )))
  expect_true("orientation_invalid" %in% issues(json(
    version = "1.1.0", primary_column = "geometry",
    columns = list(geometry = c(entry, list(orientation = "clockwise")))
  )))
  expect_true("column_not_byte_array" %in% issues(json(
    version = "1.1.0", primary_column = "id", columns = list(id = entry)
  )))
  expect_true("column_undeclared" %in% issues(
    json(version = "2.0.0", primary_column = "id", columns = list(id = entry)),
    schema = qio::parquet_schema(geometry = "GEOMETRY")
  ))
})

test_that("geo_validate_parquet() finds a grouped geometry column", {
  skip_without_qio()
  # Written by DuckDB with tools/make-parquet-fixtures.R: the geo key names a
  # struct column as WKB, which neither zugeo nor qio can write.
  v <- geo_validate_parquet(test_path("data", "geo-grouped.parquet"), metadata_only = TRUE)
  expect_true("column_grouped" %in% v$issue)
  # column_repeated needs a repeated BYTE_ARRAY at the root, the legacy
  # two-level list, which no writer zugeo's tests can reach still produces;
  # the branch (R/parquet-validate.R) stays as a guard.
})

test_that("geo_validate_parquet() finds statistics that miss their data", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  df <- data.frame(id = 1:2)
  df$geometry <- geo_points(c(0.25, 0.5), c(0.75, 0.625), crs = "OGC:CRS84")
  geo_write_parquet(df, path, sort = "none", compression = "uncompressed")
  expect_false(any(geo_validate_parquet(path)$issue %in%
    c("statistics_exceeded", "statistics_types")))
  # Patch the footer's GeospatialStatistics in place: xmax 0.5 becomes 0.375
  # (data now outside the box), and the one-type list [1] becomes [2].
  b <- readBin(path, "raw", file.size(path))
  n <- length(b)
  len <- readBin(b[(n - 7L):(n - 4L)], "integer", size = 4L, endian = "little")
  start <- n - 8L - len
  find <- function(needle, from = 1L) {
    hits <- which(vapply(seq_len(len - length(needle) + 1L), function(i) {
      all(b[start + i:(i + length(needle) - 1L)] == needle)
    }, logical(1)))
    hits[hits >= from]
  }
  xmax <- find(writeBin(0.5, raw(), size = 8L, endian = "little"))
  expect_length(xmax, 1L)
  b[start + xmax:(xmax + 7L)] <- writeBin(0.375, raw(), size = 8L, endian = "little")
  # list<i32> of one element (0x15), the zigzag varint of 1 (0x02).
  types <- find(as.raw(c(0x15, 0x02)), from = xmax + 8L)[1L]
  expect_false(is.na(types))
  b[start + types + 1L] <- as.raw(0x04)
  writeBin(b, path)
  stats <- qio::geospatial_statistics(qio::open_parquet(path))
  expect_identical(stats$xmax, 0.375)
  expect_identical(unlist(stats$geometry_types), 2L)
  v <- geo_validate_parquet(path)
  expect_true(all(c("statistics_exceeded", "statistics_types") %in% v$issue))
  expect_identical(v$row_group[v$issue == "statistics_exceeded"], 1L)
})

test_that("geo_validate_parquet() advises against row groups over 200,000 rows", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  x <- data.frame(id = seq_len(200001L))
  x$geometry <- geo_vctr(rep(NA_character_, 200001L), crs = "OGC:CRS84")
  geo_write_parquet(x, path, sort = "none", row_group_size = 300000L)
  v <- geo_validate_parquet(path, metadata_only = TRUE)
  expect_identical(v$issue[v$issue == "row_group_large"], "row_group_large")
  expect_identical(v$severity[v$issue == "row_group_large"], "warning")
})

test_that("geo_validate_parquet() finds what is wrong", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  df <- data.frame(id = 1:3)
  df$geometry <- wkb_list(c(
    "POINT (1 2)",
    "POLYGON ((0 0, 0 1, 1 1, 1 0, 0 0))",
    "LINESTRING Z (0 0 0, 50 50 1)"
  ))
  geo <- zujson::json_write(list(
    version = "1.1.0",
    primary_column = "geometry",
    columns = list(
      geometry = list(
        encoding = "WKB",
        geometry_types = list("Point", "Polygon"),
        orientation = "counterclockwise",
        edges = "karney",
        bbox = list(0, 0, 10, 10),
        epoch = "soon"
      )
    )
  ))
  p <- write_raw_parquet(df, file.path(dir, "bad.parquet"), geo = geo)
  v <- geo_validate_parquet(p)
  expect_setequal(
    v$issue[v$severity == "error"],
    c(
      "edges_invalid",
      "epoch_invalid",
      "geometry_type_undeclared",
      "orientation_wrong",
      "bbox_exceeded"
    )
  )
  expect_identical(v$row[v$issue == "geometry_type_undeclared"], 3L)
  expect_identical(v$row[v$issue == "orientation_wrong"], 2L)
  expect_identical(v$row[v$issue == "bbox_exceeded"], 3L)
  expect_true("not_zstd" %in% v$issue[v$severity == "warning"])
  meta <- geo_validate_parquet(p, metadata_only = TRUE)
  expect_false(any(c("bbox_exceeded", "orientation_wrong") %in% meta$issue))

  geo <- zujson::json_write(list(
    version = 2,
    columns = list(
      other = list(
        encoding = 1,
        geometry_types = "Point",
        crs = "EPSG:4326",
        bbox = list(1, 2)
      )
    )
  ))
  p <- write_raw_parquet(df, file.path(dir, "worse.parquet"), geo = geo)
  v <- geo_validate_parquet(p, metadata_only = TRUE)
  expect_setequal(
    v$issue,
    c(
      "version_invalid",
      "primary_column_invalid",
      "encoding_invalid",
      "geometry_types_invalid",
      "crs_invalid",
      "bbox_invalid",
      "column_missing"
    )
  )

  geo <- zujson::json_write(list(
    version = "2.0.0",
    primary_column = "geometry",
    columns = list(geometry = list(encoding = "WKB", geometry_types = list()))
  ))
  p <- write_raw_parquet(df, file.path(dir, "binary.parquet"), geo = geo)
  expect_true("native_type_missing" %in% geo_validate_parquet(p)$issue)

  df$geometry[[2L]] <- as.raw(c(1, 3, 0))
  p <- write_raw_parquet(
    df,
    file.path(dir, "wkb.parquet"),
    schema = qio::parquet_schema(geometry = "GEOMETRY")
  )
  v <- geo_validate_parquet(p)
  expect_true(all(c("geo_key_missing", "wkb_invalid") %in% v$issue))
  expect_error(
    geo_validate_parquet(p, metadata_only = NA),
    class = "zugeo_error"
  )
})

test_that("the distribution guide's advice is reported as warnings", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  withr::local_seed(3)
  n <- 400L
  x <- data.frame(id = seq_len(n))
  x$geometry <- geo_points(stats::runif(n), stats::runif(n), crs = "OGC:CRS84")
  geo_write_parquet(
    x,
    p <- file.path(dir, "random.parquet"),
    sort = "none",
    row_group_size = 50L,
    compression = "snappy"
  )
  v <- geo_validate_parquet(p)
  expect_setequal(v$issue, c("not_zstd", "not_spatially_ordered"))
  expect_true(all(v$severity == "warning"))
  geo_write_parquet(
    x,
    p <- file.path(dir, "sorted.parquet"),
    row_group_size = 50L
  )
  expect_identical(nrow(geo_validate_parquet(p)), 0L)
})

test_that("geometry findings are warnings with their rows", {
  skip_without_qio()
  dir <- withr::local_tempdir()
  x <- data.frame(id = 1:2)
  x$geometry <- geo_vctr(
    c("POINT (0 0)", "POLYGON ((0 0, 1 0, 0 1))"),
    crs = "OGC:CRS84"
  )
  geo_write_parquet(x, p <- file.path(dir, "ring.parquet"), sort = "none")
  v <- geo_validate_parquet(p)
  expect_identical(v$issue, c("unclosed_ring", "short_ring"))
  expect_identical(v$row, c(2L, 2L))
  expect_true(all(v$severity == "warning"))
})

test_that("a file with no rows reads, describes and validates", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  geo_write_parquet(geo_points(numeric(), numeric(), crs = "OGC:CRS84"), path)
  info <- geo_parquet_info(path)
  expect_identical(info$rows, 0)
  expect_identical(nrow(info$row_groups), 0L)
  expect_length(info$columns$geometry$row_group_bbox, 0L)
  for (bbox in list(NULL, c(0, 0, 1, 1))) {
    df <- geo_read_parquet(path, bbox = bbox)
    expect_identical(nrow(df), 0L)
    expect_s3_class(df$geometry, "geo_vctr")
  }
  expect_false(any(geo_validate_parquet(path)$severity == "error"))
})

test_that("bbox over non-planar edges follows the lossy policy", {
  skip_without_qio()
  path <- withr::local_tempfile(fileext = ".parquet")
  x <- data.frame(id = 1:2)
  x$geometry <- geo_vctr(c("LINESTRING (0 0, 1 1)", "LINESTRING (10 10, 11 11)"),
    crs = "OGC:CRS84", edges = "spherical"
  )
  geo_write_parquet(x, path, sort = "none")
  err <- expect_error(geo_read_parquet(path, bbox = c(0, 0, 2, 2)), class = "zugeo_edges_error")
  expect_identical(err$call[[1L]], quote(geo_read_parquet))
  expect_warning(
    w <- geo_read_parquet(path, bbox = c(0, 0, 2, 2), lossy = "warn"),
    class = "zugeo_edges_warning"
  )
  expect_identical(w$id, 1L)
  expect_identical(geo_read_parquet(path, bbox = c(0, 0, 2, 2), lossy = "allow")$id, 1L)
  # Points have no edges, so their filter is exact and needs no policy.
  p <- data.frame(id = 1:2)
  p$geometry <- geo_points(c(0.5, 10), c(0.5, 10), crs = "OGC:CRS84", edges = "spherical")
  geo_write_parquet(p, path, sort = "none")
  expect_identical(geo_read_parquet(path, bbox = c(0, 0, 2, 2))$id, 1L)
})
