# Shared by test-type-corpus.R; at file level there, a shuffled run could use it before it was defined.

corpus_expected <- function(file) {
  base <- sub("^example_", "", sub("[.]arrows$", "", file))
  encoding <- if (grepl("_", base)) sub("^.*_", "", base) else "native"
  stem <- sub("_.*$", "", base)
  type <- sub("-.*$", "", stem)
  variant <- if (grepl("-", stem)) sub("^[^-]*-", "", stem) else ""
  dims <- c(z = "xyz", m = "xym", zm = "xyzm")[variant]
  levels <- c(point = 0L, linestring = 1L, polygon = 2L, multipoint = 1L,
    multilinestring = 2L, multipolygon = 3L)[type]
  serialized <- encoding %in% c("wkb", "wkt")
  list(
    extension = if (serialized) paste0("geoarrow.", encoding) else paste0("geoarrow.", type),
    encoding = if (serialized) encoding else "native",
    geometry_type = if (serialized) "geometry" else type,
    dimensions = if (serialized) NA_character_ else if (is.na(dims)) "xy" else unname(dims),
    coord_type = if (serialized) NA_character_ else if (encoding == "interleaved") "interleaved" else "separated",
    n_offsets = if (serialized) 0L else unname(levels)
  )
}
