# GeoParquet against DuckDB, gpq and GDAL (design sections 6.9, 6.11 and 9,
# Stage 7). None is a dependency: this file is left out of the package
# tarball and runs in CI by oracles.yaml. GDAL runs in its own job from the
# files this one leaves in ZUGEO_PARQUET_OUT (tools/gdal-oracle.py).

hex_wkb <- function(x) {
  w <- geo_as_wkb(x, lossy = "allow")
  vapply(
    w,
    function(b) {
      if (is.null(b)) NA_character_ else paste(as.character(b), collapse = "")
    },
    character(1)
  )
}

test_that("DuckDB reads every file zugeo writes, value for value", {
  skip_without_oracle("duckdb")
  skip_without_qio()
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)
  for (name in names(paths)) {
    ours <- geo_read_parquet(paths[[name]])
    q <- sprintf(
      "SELECT ST_AsWKB(geometry::GEOMETRY) AS wkb FROM read_parquet('%s')",
      paths[[name]]
    )
    theirs <- DBI::dbGetQuery(con, q)$wkb
    theirs <- lapply(theirs, function(b) {
      if (is.null(b) || all(is.na(b))) NULL else as.raw(b)
    })
    got <- geo_vctr(theirs)
    expect_identical(nrow(ours), length(got), label = name)
    expect_identical(
      geo_coords(got)[c("x", "y", "feature")],
      geo_coords(ours$geometry)[c("x", "y", "feature")],
      label = name
    )
    expect_identical(geo_types(got), geo_types(ours$geometry), label = name)
    expect_identical(is.na(got), is.na(ours$geometry), label = name)
  }
})

test_that("zugeo reads what DuckDB writes, its PROJJSON CRS whole", {
  skip_without_oracle("duckdb")
  skip_without_qio()
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")
  path <- withr::local_tempfile(fileext = ".parquet")
  DBI::dbExecute(
    con,
    sprintf(
      paste(
        "COPY (SELECT 1 AS id, ST_SetCRS(ST_GeomFromText('POINT (1 2)'), 'EPSG:32618') AS geometry)",
        "TO '%s' (FORMAT parquet, GEOPARQUET_VERSION 'BOTH')"
      ),
      path
    )
  )
  df <- geo_read_parquet(path)
  crs <- geo_crs(df$geometry)
  expect_identical(crs$type, "projjson")
  expect_true(geo_crs_equal(crs, "EPSG:32618", level = "authority"))
  expect_identical(geo_as_wkt(df$geometry)[[1L]], "POINT (1 2)")
  expect_identical(
    nrow(geo_validate_parquet(path)[
      geo_validate_parquet(path)$severity == "error",
    ]),
    0L
  )
})

test_that("a covering column's statistics prune row groups", {
  skip_without_oracle("duckdb")
  skip_without_qio()
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial; SET threads = 1;")
  path <- withr::local_tempfile(fileext = ".parquet")
  geo <- zujson::json_write(list(
    version = "1.1.0",
    primary_column = "geometry",
    columns = list(
      geometry = list(
        encoding = "WKB",
        geometry_types = list("Point"),
        covering = list(
          bbox = list(
            xmin = list("bbox", "xmin"),
            ymin = list("bbox", "ymin"),
            xmax = list("bbox", "xmax"),
            ymax = list("bbox", "ymax")
          )
        )
      )
    )
  ))
  DBI::dbExecute(
    con,
    sprintf(
      paste(
        "COPY (SELECT i AS id, ST_AsWKB(ST_Point(i, i)) AS geometry,",
        "{'xmin': i::DOUBLE, 'ymin': i::DOUBLE, 'xmax': i::DOUBLE, 'ymax': i::DOUBLE} AS bbox",
        "FROM range(8192) t(i) ORDER BY i)",
        "TO '%s' (FORMAT parquet, ROW_GROUP_SIZE 2048, GEOPARQUET_VERSION 'NONE', KV_METADATA {geo: '%s'})"
      ),
      path,
      gsub("'", "''", geo)
    )
  )
  info <- geo_parquet_info(path)
  expect_gt(nrow(info$row_groups), 1L)
  ends <- cumsum(info$row_groups$rows)
  boxes <- as.data.frame(info$columns$geometry$row_group_bbox)
  expect_identical(boxes$xmin, c(0, ends[-length(ends)]))
  expect_identical(boxes$xmax, ends - 1)
  df <- geo_read_parquet(path, bbox = c(12.5, 12.5, 14.5, 14.5))
  expect_identical(as.double(df$id), c(13, 14))
  expect_false("bbox" %in% names(df))
})

# gpq's report, or, when gpq cannot validate the file at all (it prints an
# error and no report), a failure carrying its message.
gpq_report <- function(path) {
  gpq <- Sys.getenv("ZUGEO_GPQ")
  err <- tempfile()
  on.exit(unlink(err))
  out <- suppressWarnings(system2(gpq, c("validate", "--format", "json", shQuote(path)),
    stdout = TRUE, stderr = err
  ))
  text <- paste(out, collapse = "\n")
  report <- tryCatch(zujson::json_parse(text, simplify = FALSE), zujson_error = function(e) NULL)
  if (is.null(report)) {
    return(list(passed = FALSE, failed = paste("no report:", paste(readLines(err), collapse = " "))))
  }
  passed <- vapply(report$checks, function(c) isTRUE(c$passed), logical(1))
  list(passed = all(passed), failed = vapply(report$checks[!passed], `[[`, "", "title"))
}

skip_without_gpq <- function() {
  if (identical(Sys.getenv("ZUGEO_ORACLES"), "true")) {
    if (!file.exists(Sys.getenv("ZUGEO_GPQ"))) {
      stop("ZUGEO_GPQ does not name the gpq binary.")
    }
    return(invisible())
  }
  skip_if_not(file.exists(Sys.getenv("ZUGEO_GPQ")), "gpq is not installed")
}

# gpq v0.24.0 is older than parts of the specification, in four ways that
# each comparison below asserts rather than skips:
# - it predates GeoParquet 1.1's native encodings ("unsupported encoding");
# - its Arrow Go v16 panics on Parquet's GEOMETRY and GEOGRAPHY logical
#   types ("invalid logical type"), so it reads no GeoParquet 2.0 file;
# - its WKB decoder (orb) is two-dimensional, and it does not know the
#   " M" and " ZM" type names, so files with Z or M fail several checks;
# - it bounds an empty non-point geometry as (0, 0), so a file with one and a
#   bbox away from the origin fails its bbox check alone.
gpq_bbox_title <- 'all geometries must fall within the "bbox" metadata (if present)'

gpq_expected_failure <- function(path, theirs) {
  file <- basename(path)
  if (grepl("_native\\.parquet$", file)) {
    return("native encoding")
  }
  if (any(grepl("invalid logical type", theirs$failed, fixed = TRUE))) {
    return("native type")
  }
  info <- tryCatch(geo_parquet_info(path), error = function(e) NULL)
  df <- tryCatch(geo_read_parquet(path), error = function(e) NULL)
  if (is.null(df)) {
    return(NULL)
  }
  g <- df[[info$primary_column]]
  dims <- geo_dims(g)
  if (any(!is.na(dims) & dims != "xy")) {
    return("Z or M")
  }
  b <- info$columns[[info$primary_column]]$bbox
  empty <- !is.na(g) & geo_n_coords(g) == 0L & geo_types(g) != "point"
  origin_out <- !is.na(b$xmin) && !(b$xmin <= 0 && b$xmax >= 0 && b$ymin <= 0 && b$ymax >= 0)
  if (any(empty) && origin_out && identical(unname(theirs$failed), gpq_bbox_title)) {
    return("empty at origin")
  }
  NULL
}

gpq_compare <- function(path, label) {
  theirs <- gpq_report(path)
  v <- geo_validate_parquet(path)
  ours <- !any(v$severity == "error")
  why <- if (!theirs$passed && ours) gpq_expected_failure(path, theirs)
  if (!is.null(why)) {
    return(why)
  }
  expect_identical(ours, theirs$passed, label = paste(
    label, "- gpq failed:", paste(theirs$failed, collapse = "; "),
    "- zugeo found:", paste(v$issue[v$severity == "error"], collapse = ", ")
  ))
  "agree"
}

test_that("gpq validate agrees with geo_validate_parquet() on the corpus", {
  skip_without_gpq()
  skip_without_qio()
  outcome <- vapply(names(parquet_manifest()), function(file) {
    gpq_compare(parquet_corpus_path(file), file)
  }, character(1))
  # Each known limit is met where expected, and most files agree outright.
  expect_true(all(grepl("_native\\.parquet$", names(outcome)[outcome == "native encoding"])))
  expect_gt(sum(outcome == "agree"), 40L)
  expect_true(all(c("Z or M", "empty at origin") %in% outcome))
})

test_that("gpq validate agrees on the files zugeo writes", {
  skip_without_gpq()
  skip_without_qio()
  dir <- withr::local_tempdir()
  paths <- write_parquet_cases(dir)
  cases <- parquet_cases()
  for (name in names(paths)) {
    outcome <- gpq_compare(paths[[name]], name)
    version <- cases[[name]]$args$version
    if (identical(version, "1.1") || name == "code_crs") {
      # code_crs has no geo key, which gpq reports before reading the schema.
      expect_identical(outcome, "agree", label = name)
    } else {
      # 2.0 files carry the native types gpq cannot read.
      expect_identical(outcome, "native type", label = name)
    }
  }
})

test_that("the files for the GDAL oracle are written", {
  out <- Sys.getenv("ZUGEO_PARQUET_OUT")
  if (identical(Sys.getenv("ZUGEO_ORACLES"), "true") && !nzchar(out)) {
    stop("ZUGEO_PARQUET_OUT is not set, so GDAL would read nothing.")
  }
  skip_if(!nzchar(out), "ZUGEO_PARQUET_OUT is not set")
  skip_without_qio()
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  paths <- write_parquet_cases(out)
  expected <- lapply(names(paths), function(name) {
    g <- geo_read_parquet(paths[[name]])$geometry
    list(
      file = basename(paths[[name]]),
      wkb = as.list(hex_wkb(g)),
      crs = if (is.null(geo_crs(g)$value)) NULL else geo_crs_text(g)
    )
  })
  writeLines(
    as.character(zujson::json_write(expected)),
    file.path(out, "expected.json")
  )
  expect_true(file.exists(file.path(out, "expected.json")))
})
