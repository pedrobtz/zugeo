#' Versions zugeo is built from
#'
#' Reports the package version, the bundled 'geoarrow-c' library (its
#' version and the commit it is vendored from), the bundled 'nanoarrow'
#' core, and the version of the GeoArrow specification implemented.
#'
#' @return A named list of character strings: `zugeo`, `geoarrow_c`,
#'   `geoarrow_c_commit`, `nanoarrow` and `geoarrow`.
#' @export
#' @examples
#' zugeo_info()
zugeo_info <- function() {
  c(
    list(zugeo = as.character(utils::packageVersion("zugeo"))),
    .Call(zgo_c_info)
  )
}
