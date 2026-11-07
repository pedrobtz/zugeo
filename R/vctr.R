# One chunk read from Arrow: every row, in order. Validates the layout and
# metadata first, so a bad column fails as it is read.
zgo_from_array <- function(array, schema, call) {
  zgo_single_type(schema, call = call)
  n <- .Call(zgo_c_array_length, array)
  if (n > .Machine$integer.max) {
    zgo_abort(NULL, "A GeoArrow array longer than 2^31 - 1 rows is not supported yet.",
      call = call
    )
  }
  zgo_vctr_new(seq_len(n), list(array), schema)
}

zgo_vctr_new <- function(positions, chunks, schema) {
  lengths <- vapply(chunks, function(a) .Call(zgo_c_array_length, a), numeric(1))
  structure(
    as.integer(positions),
    chunks = chunks,
    starts = c(0, cumsum(lengths))[seq_along(chunks)],
    schema = schema,
    class = "geo_vctr"
  )
}

# The chunk (0-based) and row (0-based) of each position; NA for NA.
zgo_locate <- function(x) {
  pos <- as.numeric(unclass(x))
  attributes(pos) <- NULL
  starts <- attr(x, "starts")
  k <- findInterval(pos - 1, starts)
  row <- pos - 1 - starts[k]
  list(chunk = as.integer(k - 1L), row = as.numeric(row))
}

zgo_rebuild <- function(x, positions) {
  structure(
    as.integer(positions),
    chunks = attr(x, "chunks"),
    starts = attr(x, "starts"),
    schema = attr(x, "schema"),
    class = "geo_vctr"
  )
}

#' @export
`[.geo_vctr` <- function(x, i) {
  zgo_rebuild(x, unclass(x)[i])
}

#' @export
`[[.geo_vctr` <- function(x, i) {
  zgo_rebuild(x, unclass(x)[[i]])
}

#' @export
`[<-.geo_vctr` <- function(x, i, value) {
  zgo_abort(NULL, "A geo_vctr cannot be modified in place; combine with c().",
    call = sys.call()
  )
}

#' @export
`[[<-.geo_vctr` <- `[<-.geo_vctr`

#' @export
`length<-.geo_vctr` <- function(x, value) {
  n <- length(x)
  if (value <= n) {
    return(x[seq_len(value)])
  }
  zgo_rebuild(x, c(unclass(x), rep(NA_integer_, value - n)))
}

#' @export
is.na.geo_vctr <- function(x) {
  loc <- zgo_locate(x)
  .Call(zgo_c_is_na, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row)
}

#' @export
c.geo_vctr <- function(...) {
  call <- sys.call()
  parts <- Filter(Negate(is.null), list(...))
  if (!all(vapply(parts, is_geo_vctr, logical(1)))) {
    zgo_abort(NULL, "Only geo_vctr objects can be combined with a geo_vctr.",
      call = call
    )
  }
  first <- parts[[1L]]
  chunks <- attr(first, "chunks")
  starts <- attr(first, "starts")
  positions <- list(unclass(first))
  total <- zgo_total_rows(first)
  for (part in parts[-1L]) {
    zgo_check_combinable(first, part, call)
    p <- as.numeric(unclass(part)) + total
    if (any(p > .Machine$integer.max, na.rm = TRUE)) {
      zgo_abort(NULL, "Combined geo_vctr has more than 2^31 - 1 rows.", call = call)
    }
    positions <- c(positions, list(as.integer(p)))
    chunks <- c(chunks, attr(part, "chunks"))
    starts <- c(starts, attr(part, "starts") + total)
    total <- total + zgo_total_rows(part)
  }
  positions <- unlist(lapply(positions, function(p) {
    attributes(p) <- NULL
    p
  }))
  structure(
    positions,
    chunks = chunks,
    starts = starts,
    schema = attr(first, "schema"),
    class = "geo_vctr"
  )
}

zgo_total_rows <- function(x) {
  chunks <- attr(x, "chunks")
  if (length(chunks) == 0L) {
    return(0)
  }
  last <- chunks[[length(chunks)]]
  attr(x, "starts")[[length(chunks)]] + .Call(zgo_c_array_length, last)
}

# Two vectors combine when their schemas are the same, metadata included
# (design section 6.1): chunks of one column. A different CRS or edge type
# is a zugeo_crs_error; any other difference needs a conversion first.
zgo_check_combinable <- function(x, y, call) {
  sx <- attr(x, "schema")
  sy <- attr(y, "schema")
  if (isTRUE(zuarrow::arrow_equal(sx, sy, metadata = TRUE))) {
    return(invisible())
  }
  tx <- zgo_single_type(sx, call = call)
  ty <- zgo_single_type(sy, call = call)
  if (!geo_crs_equal(tx$crs, ty$crs) || !identical(tx$edges, ty$edges)) {
    zgo_abort(
      "crs",
      sprintf(
        "Cannot combine geometries with different CRS or edges (%s, %s; %s, %s).",
        format(tx$crs), tx$edges, format(ty$crs), ty$edges
      ),
      call = call
    )
  }
  zgo_abort(
    "layout",
    sprintf(
      "Cannot combine %s with %s; convert one to the other's layout first.",
      format(tx), format(ty)
    ),
    call = call
  )
}

#' @export
format.geo_vctr <- function(x, ..., max_bytes = 1000L) {
  loc <- zgo_locate(x)
  out <- .Call(
    zgo_c_format, attr(x, "chunks"), attr(x, "schema"),
    loc$chunk, loc$row, as.numeric(max_bytes)
  )
  out[is.na(out)] <- "<null>"
  out
}

#' @export
as.character.geo_vctr <- function(x, ...) {
  out <- format(x, ...)
  out[is.na(x)] <- NA_character_
  out
}

#' @export
print.geo_vctr <- function(x, ..., width = getOption("width")) {
  type <- zgo_single_type(attr(x, "schema"), call = sys.call())
  cat(sprintf("<geo_vctr[%d] %s>\n", length(x), sub("^<(.*)>$", "\\1", format(type))))
  n <- min(length(x), 20L)
  if (n > 0L) {
    text <- format(x[seq_len(n)], max_bytes = max(width - 8L, 20L))
    text <- ifelse(nchar(text) > width - 8L, paste0(substr(text, 1L, width - 11L), "..."), text)
    cat(paste0("[", seq_len(n), "] ", text), sep = "\n")
    if (length(x) > n) cat(sprintf("... and %d more\n", length(x) - n))
  }
  invisible(x)
}

#' @export
as.data.frame.geo_vctr <- function(x, row.names = NULL, optional = FALSE, ...,
                                   nm = deparse1(substitute(x))) {
  as.data.frame.vector(x, row.names = row.names, optional = optional, ..., nm = nm)
}

#' @export
rep.geo_vctr <- function(x, ...) {
  zgo_rebuild(x, rep(unclass(x), ...))
}

# Export: the rows in order as one array of the vector's own type. A vector
# that is still exactly the one chunk it was read as is that chunk, byte for
# byte.
zgo_to_array <- function(x) {
  chunks <- attr(x, "chunks")
  positions <- unclass(x)
  attributes(positions) <- NULL
  if (length(chunks) == 1L &&
    length(positions) == .Call(zgo_c_array_length, chunks[[1L]]) &&
    identical(positions, seq_len(length(positions)))) {
    return(chunks[[1L]])
  }
  loc <- zgo_locate(x)
  .Call(zgo_c_take, chunks, attr(x, "schema"), loc$chunk, loc$row)
}
