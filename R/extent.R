#' Extents: boxes as a vector
#'
#' A `geo_extent` is the one box type zugeo uses (design D16): what
#' [geo_box()] returns, what index queries take. Each element is
#' `xmin`, `ymin`, `xmax`, `ymax`, with `zmin`, `zmax`, `mmin`, `mmax` when
#' given, and the vector carries the CRS and edge type of its geometries.
#' An empty geometry's box is all `NaN` and a null's is `NA`; both are
#' disjoint from everything.
#'
#' `geo_extent_union()` reduces to the one box covering every element;
#' `geo_extent_intersection()` and `geo_extent_intersects()` work pairwise,
#' recycling. A box with `xmin > xmax`, which GeoArrow uses for boxes that
#' cross the antimeridian, is a `zugeo_edges_error` in all three rather than
#' read as planar.
#'
#' @param xmin,ymin,xmax,ymax,zmin,zmax,mmin,mmax Numeric bounds, recycled.
#'   `zmin` and `zmax` come together, as do `mmin` and `mmax`.
#' @param crs,edges As for [geo_vctr()].
#' @param e,f `geo_extent` vectors.
#' @return `geo_extent()`, `geo_extent_union()` and
#'   `geo_extent_intersection()`: a `geo_extent`. `geo_extent_intersects()`:
#'   a logical vector.
#' @export
#' @examples
#' e <- geo_extent(c(0, 5), c(0, 5), c(2, 6), c(2, 6))
#' geo_extent_union(e)
#' geo_extent_intersects(e, geo_extent(1, 1, 1.5, 1.5))
geo_extent <- function(xmin, ymin, xmax, ymax, zmin = NULL, zmax = NULL,
                       mmin = NULL, mmax = NULL, crs = NULL, edges = NULL) {
  call <- sys.call()
  if (xor(is.null(zmin), is.null(zmax)) || xor(is.null(mmin), is.null(mmax))) {
    zgo_abort(NULL, "`zmin` and `zmax`, and `mmin` and `mmax`, come in pairs.", call = call)
  }
  parts <- list(xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax,
    zmin = zmin, zmax = zmax, mmin = mmin, mmax = mmax)
  parts <- Filter(Negate(is.null), parts)
  ok <- vapply(parts, function(p) is.numeric(p) || all(is.na(p)), logical(1))
  if (!all(ok)) {
    zgo_abort(NULL, "Extent bounds must be numeric.", call = call)
  }
  n <- max(lengths(parts))
  if (any(lengths(parts) == 0L)) n <- 0L
  parts <- lapply(parts, function(p) rep_len(as.double(p), n))
  zgo_extent_new(parts, geo_crs(crs), zgo_check_edges(edges, call))
}

zgo_extent_new <- function(parts, crs, edges) {
  structure(parts, crs = crs, edges = edges, class = "geo_extent")
}

zgo_extent_parts <- function(e) {
  out <- unclass(e)
  attributes(out) <- list(names = names(e))
  out
}

#' @export
length.geo_extent <- function(x) length(unclass(x)$xmin)

#' @export
names.geo_extent <- function(x) names(unclass(x))

#' @export
`[.geo_extent` <- function(x, i) {
  parts <- lapply(zgo_extent_parts(x), function(p) p[i])
  zgo_extent_new(parts, attr(x, "crs"), attr(x, "edges"))
}

#' @export
`$.geo_extent` <- function(x, name) unclass(x)[[name]]

#' @export
`[[.geo_extent` <- function(x, i) {
  if (is.character(i)) {
    return(unclass(x)[[i]])
  }
  x[i]
}

#' @export
is.na.geo_extent <- function(x) is.na(unclass(x)$xmin) & !is.nan(unclass(x)$xmin)

#' @export
c.geo_extent <- function(...) {
  call <- sys.call()
  parts <- Filter(Negate(is.null), list(...))
  if (!all(vapply(parts, inherits, logical(1), "geo_extent"))) {
    zgo_abort(NULL, "Only geo_extent objects combine with a geo_extent.", call = call)
  }
  first <- parts[[1L]]
  for (p in parts[-1L]) {
    zgo_extent_check_same(first, p, call)
    if (!identical(names(p), names(first))) {
      zgo_abort(NULL, "Extents with different dimensions do not combine.", call = call)
    }
  }
  out <- lapply(names(first), function(k) unlist(lapply(parts, function(p) unclass(p)[[k]])))
  names(out) <- names(first)
  zgo_extent_new(out, attr(first, "crs"), attr(first, "edges"))
}

zgo_extent_check_same <- function(e, f, call) {
  if (!geo_crs_equal(attr(e, "crs"), attr(f, "crs")) ||
    !identical(attr(e, "edges"), attr(f, "edges"))) {
    zgo_abort(
      "crs",
      "Extents with different CRS or edges cannot be compared or combined.",
      call = call
    )
  }
}

zgo_extent_check_planar <- function(e, call) {
  p <- zgo_extent_parts(e)
  if (any(p$xmin > p$xmax, na.rm = TRUE)) {
    zgo_abort(
      "edges",
      paste(
        "An extent has xmin > xmax, which crosses the antimeridian; planar set",
        "operations would misread it."
      ),
      call = call
    )
  }
}

#' @export
format.geo_extent <- function(x, ...) {
  p <- zgo_extent_parts(x)
  num <- function(v) ifelse(is.na(v) & !is.nan(v), "NA", as.character(v))
  lo <- c("xmin", "ymin", intersect(c("zmin", "mmin"), names(p)))
  hi <- c("xmax", "ymax", intersect(c("zmax", "mmax"), names(p)))
  if (length(x) == 0L) return(character())
  lo_text <- do.call(paste, lapply(p[lo], num))
  hi_text <- do.call(paste, lapply(p[hi], num))
  out <- sprintf("[%s, %s]", lo_text, hi_text)
  out[is.na(x)] <- "<null>"
  out
}

#' @export
print.geo_extent <- function(x, ...) {
  cat(sprintf("<geo_extent[%d]; crs %s; edges %s>\n", length(x),
    sub("^<zugeo_crs:? ?(.*)>$", "\\1", format(attr(x, "crs"))), attr(x, "edges")))
  if (length(x)) cat(paste0("[", seq_along(x), "] ", format(x)), sep = "\n")
  invisible(x)
}

#' @export
as.data.frame.geo_extent <- function(x, ...) {
  as.data.frame(zgo_extent_parts(x))
}

#' @rdname geo_extent
#' @export
geo_extent_union <- function(e) {
  call <- sys.call()
  zgo_check_extent(e, call)
  zgo_extent_check_planar(e, call)
  p <- zgo_extent_parts(e)
  # Null and empty boxes cover nothing; within the rest, a dimension only
  # some boxes have (a 2D point beside a 3D line) is NaN in the others.
  keep <- !is.na(p$xmin)
  reduce <- function(v, f) {
    v <- v[keep & !is.na(v)]
    if (length(v)) f(v) else NaN
  }
  out <- lapply(names(p), function(k) {
    reduce(p[[k]], if (endsWith(k, "min")) min else max)
  })
  names(out) <- names(p)
  zgo_extent_new(out, attr(e, "crs"), attr(e, "edges"))
}

#' @rdname geo_extent
#' @export
geo_extent_intersection <- function(e, f) {
  call <- sys.call()
  zgo_extent_pair(e, f, call)
  pe <- zgo_extent_parts(e)
  pf <- zgo_extent_parts(f)
  n <- if (length(e) == 0L || length(f) == 0L) 0L else max(length(e), length(f))
  dims <- intersect(c("x", "y", "z", "m"), sub("min$", "", intersect(names(pe), names(pf))))
  out <- list()
  empty <- rep(FALSE, n)
  null <- rep_len(is.na(e), n) | rep_len(is.na(f), n)
  for (d in dims) {
    lo <- pmax(rep_len(pe[[paste0(d, "min")]], n), rep_len(pf[[paste0(d, "min")]], n))
    hi <- pmin(rep_len(pe[[paste0(d, "max")]], n), rep_len(pf[[paste0(d, "max")]], n))
    empty <- empty | (!is.na(lo) & !is.na(hi) & lo > hi) | is.nan(lo) | is.nan(hi)
    out[[paste0(d, "min")]] <- lo
    out[[paste0(d, "max")]] <- hi
  }
  out <- out[c(paste0(dims[1:2], "min"), paste0(dims[1:2], "max"),
    unlist(lapply(dims[-(1:2)], function(d) paste0(d, c("min", "max")))))]
  out <- lapply(out, function(v) {
    v[empty & !null] <- NaN
    v[null] <- NA_real_
    v
  })
  zgo_extent_new(out, attr(e, "crs"), attr(e, "edges"))
}

#' @rdname geo_extent
#' @export
geo_extent_intersects <- function(e, f) {
  call <- sys.call()
  zgo_extent_pair(e, f, call)
  i <- zgo_extent_parts(geo_extent_intersection(e, f))
  !is.na(i$xmin)
}

zgo_check_extent <- function(e, call) {
  if (!inherits(e, "geo_extent")) {
    zgo_abort(NULL, "Expected a geo_extent.", call = call)
  }
}

zgo_extent_pair <- function(e, f, call) {
  zgo_check_extent(e, call)
  zgo_check_extent(f, call)
  zgo_extent_check_same(e, f, call)
  zgo_extent_check_planar(e, call)
  zgo_extent_check_planar(f, call)
}
