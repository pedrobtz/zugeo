# An Arrow schema handle from a spec: list(format, name, flags, metadata,
# children), each child a spec. The handle has nanoarrow's layout, so
# zuarrow and nanoarrow read it.
zgo_schema <- function(spec) {
  .Call(zgo_c_schema_from_spec, spec)
}

zgo_spec <- function(format, name = "", metadata = NULL, children = list(),
                     nullable = TRUE) {
  list(
    format = format,
    name = name,
    flags = if (nullable) 2L else 0L,
    metadata = metadata,
    children = children
  )
}
