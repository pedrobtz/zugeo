# Shared by test-ci-parquet.R; at file level there, a shuffled run could use it before it was defined.

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
