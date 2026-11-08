# Shared by test-parquet-corpus.R; at file level there, a shuffled run could use it before it was defined.

# WKT without the `crs` attribute: the plain files state OGC:CRS84, the
# Parquet default, where their geo key twins and IPC files state none.
bare_wkt <- function(x) {
  out <- geo_as_wkt(x, lossy = "allow")
  attributes(out) <- NULL
  out
}
parquet_wkb_files <- function() {
  files <- parquet_corpus_files()
  files[!grepl("_native\\.parquet$", files)]
}
