# The geoarrow-data example files (design section 9), at a pinned commit.
# geoarrow-data carries no licence, so the files are not shipped in the
# package: tests fetch them when ZUGEO_FETCH_FIXTURES=true (CI) or read them
# from ZUGEO_CORPUS_DIR, and skip otherwise. corpus.txt pins each file's
# md5.

corpus_commit <- "e8eaa04487d982398f07713cde527c5c5edeee1e"

corpus_manifest <- function() {
  lines <- readLines(test_path("corpus.txt"))
  lines <- lines[!startsWith(lines, "#")]
  stats::setNames(sub(" .*$", "", lines), sub("^[^ ]+ ", "", lines))
}

corpus_env <- new.env(parent = emptyenv())

corpus_dir <- function() {
  dir <- Sys.getenv("ZUGEO_CORPUS_DIR")
  if (nzchar(dir)) {
    return(corpus_verified(dir))
  }
  if (!is.null(corpus_env$dir)) {
    return(corpus_env$dir)
  }
  if (!identical(Sys.getenv("ZUGEO_FETCH_FIXTURES"), "true")) {
    skip("The geoarrow-data corpus is fetched only with ZUGEO_FETCH_FIXTURES=true.")
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
    if (ok) break
    Sys.sleep(2^attempt)
  }
  if (!ok) {
    stop("Could not download the geoarrow-data corpus from ", url)
  }
  prefix <- sprintf("geoarrow-data-%s/example/files/", corpus_commit)
  utils::untar(archive, files = paste0(prefix, names(corpus_manifest())), exdir = dest)
  corpus_env$dir <- corpus_verified(file.path(dest, prefix))
  corpus_env$dir
}

corpus_verified <- function(dir) {
  manifest <- corpus_manifest()
  actual <- tools::md5sum(file.path(dir, names(manifest)))
  bad <- names(manifest)[is.na(actual) | unname(actual) != manifest]
  if (length(bad) > 0L) {
    stop("Corpus files missing or changed: ", paste(bad, collapse = ", "))
  }
  dir
}

corpus_path <- function(file) file.path(corpus_dir(), file)

corpus_schema <- function(file) {
  zuarrow::arrow_schema(zuarrow::arrow_read(corpus_path(file), lazy = TRUE))
}
