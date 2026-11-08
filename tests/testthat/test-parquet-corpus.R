# GeoParquet over the geoarrow-data corpus (design sections 6.9, 6.11 and
# 9, Stage 7): its 1.0 files with a geo key (`_geo`), its files with native
# GEOMETRY types and no geo key, and its 1.1 native-encoding files
# (`_native`), which need nested reads qio does not have yet.

test_that("every WKB corpus file reads, equal to its IPC twin", {
  skip_without_qio()
  ipc <- names(corpus_manifest())
  for (file in parquet_wkb_files()) {
    df <- geo_read_parquet(parquet_corpus_path(file))
    expect_s3_class(df$geometry, "geo_vctr")
    stem <- sub("(_geo)?\\.parquet$", "", basename(file))
    twin <- paste0(stem, "_wkb.arrows")
    if (twin %in% ipc) {
      want <- zuarrow::arrow_read(corpus_path(twin))$geometry
      expect_identical(bare_wkt(df$geometry), bare_wkt(want), label = file)
    }
  }
})

test_that("a file's geo key and native twin read to the same geometries", {
  skip_without_qio()
  for (file in grep("_geo\\.parquet$", parquet_wkb_files(), value = TRUE)) {
    twin <- sub("_geo\\.parquet$", ".parquet", file)
    a <- geo_read_parquet(parquet_corpus_path(file))$geometry
    b <- geo_read_parquet(parquet_corpus_path(twin))$geometry
    expect_identical(bare_wkt(a), bare_wkt(b), label = file)
  }
})

test_that("the corpus CRSs are read as the files state them", {
  skip_without_qio()
  crs <- function(file) {
    geo_crs(geo_read_parquet(parquet_corpus_path(file))$geometry)
  }
  expect_identical(
    crs("example-crs/files/example-crs_vermont-crs84.parquet")$value,
    "OGC:CRS84"
  )
  utm <- crs("example-crs/files/example-crs_vermont-utm_geo.parquet")
  expect_identical(utm$type, "projjson")
  expect_identical(utm$value$name, "WGS 84 / UTM zone 18N")
  # The native twin's PROJJSON came from another PROJ version: the same code,
  # different members.
  native <- crs("example-crs/files/example-crs_vermont-utm.parquet")
  expect_identical(native$type, "projjson")
  expect_false(geo_crs_equal(utm, native, level = "structural"))
  expect_true(geo_crs_equal(utm, native, level = "authority"))
  wkt2 <- crs("example-crs/files/example-crs_vermont-crs84-wkt2.parquet")
  expect_identical(wkt2$type, "wkt2:2019")
  expect_null(crs("example/files/example_point_geo.parquet")$value)
})

test_that("GeoArrow-encoded corpus files are a zugeo_parquet_error", {
  skip_without_qio()
  for (file in grep(
    "_native\\.parquet$",
    parquet_corpus_files(),
    value = TRUE
  )) {
    expect_error(
      geo_read_parquet(parquet_corpus_path(file)),
      class = "zugeo_parquet_error",
      label = file
    )
    info <- geo_parquet_info(parquet_corpus_path(file))
    expect_true(
      info$columns$geometry$encoding %in% zgo_geoarrow_encodings,
      label = file
    )
  }
})

test_that("every WKB corpus file round-trips through geo_write_parquet()", {
  skip_without_qio()
  out <- withr::local_tempfile(fileext = ".parquet")
  for (file in parquet_wkb_files()) {
    df <- geo_read_parquet(parquet_corpus_path(file))
    if (identical(geo_crs(df$geometry)$type, "wkt2:2019")) {
      # 1.5 KB of WKT2 fits neither the Parquet type nor the geo key.
      expect_error(geo_write_parquet(df, out), class = "zugeo_crs_error")
      next
    }
    geo_write_parquet(df, out, sort = "none")
    back <- geo_read_parquet(out)
    expect_identical(
      bare_wkt(back$geometry),
      bare_wkt(df$geometry),
      label = file
    )
    expect_true(geo_crs_equal(back$geometry, df$geometry), label = file)
  }
})

test_that("geo_validate_parquet() finds no errors in the corpus beyond missing geo keys", {
  skip_without_qio()
  for (file in parquet_corpus_files()) {
    v <- geo_validate_parquet(parquet_corpus_path(file))
    errors <- v$issue[v$severity == "error"]
    want <- if (grepl("_(geo|native)\\.parquet$", file)) {
      character()
    } else {
      "geo_key_missing"
    }
    expect_identical(errors, want, label = file)
  }
})
