# The geoarrow-data example files (design section 9), at a pinned commit.
# geoarrow-data carries no licence, so the files are not shipped in the
# package: tests fetch them when ZUGEO_FETCH_FIXTURES=true (CI) or read them
# from ZUGEO_CORPUS_DIR, and skip otherwise. corpus.txt pins each file's
# md5.

corpus_commit <- "e8eaa04487d982398f07713cde527c5c5edeee1e"

corpus_read_manifest <- function(file) {
  lines <- readLines(test_path(file))
  lines <- lines[!startsWith(lines, "#")]
  stats::setNames(sub(" .*$", "", lines), sub("^[^ ]+ ", "", lines))
}

# The IPC files, relative to example/files.
corpus_manifest <- function() corpus_read_manifest("corpus.txt")

# The Parquet files, relative to the repository root.
parquet_manifest <- function() corpus_read_manifest("corpus-parquet.txt")

# The Parquet files the corpus tests loop over. Under gctorture (r-actions
# sets R_ACTIONS_WORKFLOW) a fixed sample of each kind: all 124, each read,
# written and validated, took step 20 past the job's four hours, and zugeo's
# own C on this path is the WKB reader and writer, which the sample and the
# unit tests reach.
parquet_corpus_files <- function() {
  files <- names(parquet_manifest())
  if (identical(Sys.getenv("R_ACTIONS_WORKFLOW"), "gctorture")) {
    keep <- "example_(point|polygon-z|geometrycollection)(_geo|_native)?\\.parquet$|vermont-(utm|crs84-wkt2)"
    files <- files[grepl(keep, files)]
  }
  files
}

corpus_env <- new.env(parent = emptyenv())

# The geoarrow-data checkout: the parent of ZUGEO_CORPUS_DIR's example/files,
# or the pinned commit fetched once per session, with every manifest file.
corpus_root <- function() {
  dir <- Sys.getenv("ZUGEO_CORPUS_DIR")
  if (nzchar(dir)) {
    return(normalizePath(file.path(dir, "..", "..")))
  }
  if (!is.null(corpus_env$root)) {
    return(corpus_env$root)
  }
  if (!identical(Sys.getenv("ZUGEO_FETCH_FIXTURES"), "true")) {
    skip(
      "The geoarrow-data corpus is fetched only with ZUGEO_FETCH_FIXTURES=true."
    )
  }
  dest <- file.path(tempdir(), "zugeo-corpus")
  dir.create(dest, showWarnings = FALSE)
  archive <- file.path(dest, "geoarrow-data.tar.gz")
  url <- sprintf(
    "https://codeload.github.com/geoarrow/geoarrow-data/tar.gz/%s",
    corpus_commit
  )
  ok <- FALSE
  for (attempt in 1:3) {
    ok <- tryCatch(
      utils::download.file(url, archive, mode = "wb", quiet = TRUE) == 0L,
      error = function(e) FALSE,
      warning = function(w) FALSE
    )
    if (ok) {
      break
    }
    Sys.sleep(2^attempt)
  }
  if (!ok) {
    stop("Could not download the geoarrow-data corpus from ", url)
  }
  prefix <- sprintf("geoarrow-data-%s/", corpus_commit)
  files <- c(
    paste0(prefix, "example/files/", names(corpus_manifest())),
    paste0(prefix, names(parquet_manifest()))
  )
  utils::untar(archive, files = files, exdir = dest)
  corpus_env$root <- file.path(dest, prefix)
  corpus_env$root
}

corpus_dir <- function() {
  if (is.null(corpus_env$dir)) {
    corpus_env$dir <- corpus_verified(
      file.path(corpus_root(), "example", "files"),
      corpus_manifest()
    )
  }
  corpus_env$dir
}

parquet_corpus_dir <- function() {
  if (is.null(corpus_env$parquet)) {
    corpus_env$parquet <- corpus_verified(corpus_root(), parquet_manifest())
  }
  corpus_env$parquet
}

corpus_verified <- function(dir, manifest) {
  actual <- tools::md5sum(file.path(dir, names(manifest)))
  bad <- names(manifest)[is.na(actual) | unname(actual) != manifest]
  if (length(bad) > 0L) {
    stop("Corpus files missing or changed: ", paste(bad, collapse = ", "))
  }
  dir
}

parquet_corpus_path <- function(file) file.path(parquet_corpus_dir(), file)

corpus_path <- function(file) file.path(corpus_dir(), file)

corpus_schema <- function(file) {
  zuarrow::arrow_schema(zuarrow::arrow_read(corpus_path(file), lazy = TRUE))
}
