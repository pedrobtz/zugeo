# Shared by test-ci-index.R; at file level there, a shuffled run could use it before it was defined.

skip_without_tool <- function(var) {
  value <- Sys.getenv(var)
  if (!nzchar(value)) {
    if (identical(Sys.getenv("ZUGEO_ORACLES"), "true")) stop(var, " is not set.")
    skip(paste(var, "is not set."))
  }
  value
}
write_inputs <- function(e, node_size, kd_node_size) {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  p <- as.data.frame(e)
  writeLines(c("xmin,ymin,xmax,ymax", sprintf("%.17g,%.17g,%.17g,%.17g", p$xmin, p$ymin, p$xmax, p$ymax)),
    file.path(dir, "boxes.csv"))
  writeBin(geo_index_raw(geo_rtree(e, node_size = node_size)), file.path(dir, "rtree.bin"))
  writeBin(geo_index_raw(geo_kdtree(geo_points(p$xmin, p$ymin), node_size = kd_node_size)),
    file.path(dir, "kd.bin"))
  dir
}
