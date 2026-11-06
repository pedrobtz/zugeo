# GeoArrow schemas built from specs, for tests that need no corpus file.

ga_coord <- function(dims = "xy", coord = "separated") {
  if (coord == "separated") {
    zgo_spec("+s", "", nullable = FALSE, children = lapply(
      strsplit(dims, "")[[1]],
      function(d) zgo_spec("g", d, nullable = FALSE)
    ))
  } else {
    zgo_spec(paste0("+w:", nchar(dims)), "", nullable = FALSE, children = list(
      zgo_spec("g", dims, nullable = FALSE)
    ))
  }
}

ga_list <- function(child, name = "", large = FALSE) {
  zgo_spec(if (large) "+L" else "+l", name, nullable = FALSE,
    children = list(child)
  )
}

ga_native <- function(type, dims = "xy", coord = "separated", large = FALSE) {
  levels <- c(point = 0, linestring = 1, polygon = 2, multipoint = 1,
    multilinestring = 2, multipolygon = 3)[[type]]
  spec <- ga_coord(dims, coord)
  for (i in seq_len(levels)) {
    spec <- ga_list(spec, large = large)
  }
  spec
}

ga_field <- function(spec, extension, metadata = NULL, name = "geometry") {
  spec$name <- name
  spec$flags <- 2L
  spec$metadata <- c(
    "ARROW:extension:name" = extension,
    if (!is.null(metadata)) c("ARROW:extension:metadata" = metadata)
  )
  spec
}

ga_schema <- function(type, ..., metadata = NULL) {
  spec <- ga_native(type, ...)
  zgo_schema(ga_field(spec, paste0("geoarrow.", type), metadata))
}

ga_union <- function(ids, dims_of = function(id) c("xy", "xyz", "xym", "xyzm")[id %/% 10 + 1]) {
  types <- c("point", "linestring", "polygon", "multipoint", "multilinestring",
    "multipolygon")
  children <- lapply(ids, function(id) {
    t <- id %% 10
    if (t == 7) {
      inner <- ga_union(c(1, 2) + 10 * (id %/% 10))
      inner$name <- ""
      return(ga_list(inner, name = "GeometryCollection"))
    }
    spec <- ga_native(types[[t]], dims_of(id))
    spec$name <- types[[t]]
    spec
  })
  zgo_spec(paste0("+ud:", paste(ids, collapse = ",")), "", nullable = FALSE,
    children = children
  )
}
