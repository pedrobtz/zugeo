#' Packed spatial indexes
#'
#' `geo_rtree()` packs each geometry's box into a static R-tree, and
#' `geo_kdtree()` packs points into a static k-d tree (design section 6.8).
#' Both are immutable, bulk-loaded and held as one raw vector in flatbush's
#' and kdbush's serialised formats, so `geo_index_raw()` gives bytes that
#' flatbush and kdbush in JavaScript and geo-index in Rust and Python load
#' unchanged, and `geo_index_from_raw()` reads such bytes back, checking
#' them first.
#'
#' Null and empty geometries are left out of an index, and queries return
#' positions in the vector the index was built from. An index read from raw
#' bytes numbers its items 1 to n in the order they were added.
#'
#' @param x A `geo_vctr` or a `geo_extent` for `geo_rtree()`; a `geo_vctr`
#'   of points for `geo_kdtree()`.
#' @param node_size Entries per node, 2 to 65535: flatbush's default of 16
#'   for R-trees and kdbush's 64 for k-d trees.
#' @param lossy As for [geo_box()].
#' @param index A `zugeo_index`.
#' @param raw A raw vector holding a flatbush or kdbush index.
#' @return `geo_rtree()`, `geo_kdtree()` and `geo_index_from_raw()`: a
#'   `zugeo_index`. `geo_index_raw()`: a raw vector.
#' @seealso [geo_query_box()] for queries and joins.
#' @export
#' @examples
#' x <- geo_points(c(0, 5, 9), c(0, 5, 9))
#' tree <- geo_rtree(x)
#' geo_query_box(tree, geo_extent(4, 4, 10, 10))
#' bytes <- geo_index_raw(tree)
#' geo_query_box(geo_index_from_raw(bytes), geo_extent(4, 4, 10, 10))
geo_rtree <- function(x, node_size = 16L, lossy = c("error", "warn", "allow")) {
  call <- sys.call()
  lossy <- zgo_match_arg(lossy)
  node_size <- zgo_check_node_size(node_size, call)
  box <- if (inherits(x, "geo_extent")) x else geo_box(x, lossy = lossy)
  zgo_extent_check_planar(box, call)
  p <- zgo_extent_parts(box)
  rows <- which(!is.na(p$xmin))
  if (length(rows) == 0L) {
    zgo_abort("index", "An R-tree needs at least one geometry that is neither null nor empty.",
      call = call
    )
  }
  raw <- .Call(zgo_c_rtree_build, p$xmin[rows], p$ymin[rows], p$xmax[rows], p$ymax[rows], node_size)
  zgo_index_new(raw, "rtree", rows, length(box), attr(box, "crs"), attr(box, "edges"))
}

#' @rdname geo_rtree
#' @export
geo_kdtree <- function(x, node_size = 64L) {
  call <- sys.call()
  zgo_check_vctr(x, call)
  node_size <- zgo_check_node_size(node_size, call)
  types <- geo_types(x)
  if (any(!is.na(types) & types != "point")) {
    zgo_abort("index", "A k-d tree holds points; use geo_rtree() for other geometries.",
      call = call
    )
  }
  b <- zgo_extent_parts(geo_box(x))
  rows <- which(!is.na(b$xmin))
  raw <- .Call(zgo_c_kdtree_build, b$xmin[rows], b$ymin[rows], node_size)
  type <- geo_type_of(x)
  zgo_index_new(raw, "kdtree", rows, length(x), type$crs, type$edges)
}

zgo_check_node_size <- function(node_size, call) {
  if (!(is.numeric(node_size) && length(node_size) == 1L && !is.na(node_size) &&
    node_size == round(node_size) && node_size >= 2 && node_size <= 65535)) {
    zgo_abort(NULL, "`node_size` must be a whole number from 2 to 65535.", call = call)
  }
  as.integer(node_size)
}

zgo_index_new <- function(raw, type, rows, n, crs, edges) {
  info <- zgo_check(.Call(zgo_c_index_info, raw))
  structure(
    list(raw = raw, rows = as.integer(rows), n = as.integer(n)),
    type = type, node_size = info$node_size, crs = crs, edges = edges,
    class = c(paste0("zugeo_", type), "zugeo_index")
  )
}

#' @export
print.zugeo_index <- function(x, ...) {
  cat(sprintf(
    "<zugeo_index %s: %d items of %d, node size %d, %d bytes; crs %s>\n",
    attr(x, "type"), length(x$rows), x$n, attr(x, "node_size"), length(x$raw),
    sub("^<zugeo_crs:? ?(.*)>$", "\\1", format(attr(x, "crs")))
  ))
  invisible(x)
}

#' @rdname geo_rtree
#' @export
geo_index_raw <- function(index) {
  zgo_check_index(index, NULL, sys.call())
  index$raw
}

#' @rdname geo_rtree
#' @export
geo_index_from_raw <- function(raw) {
  call <- sys.call()
  if (!is.raw(raw)) {
    zgo_abort("index", "An index is a raw vector.", call = call)
  }
  info <- zgo_check(.Call(zgo_c_index_info, raw), call = call)
  n <- as.integer(info$n_items)
  zgo_index_new(raw, info$type, seq_len(n), n, geo_crs(NULL), "planar")
}

zgo_check_index <- function(index, type, call) {
  if (!inherits(index, "zugeo_index")) {
    zgo_abort(NULL, "`index` must be a zugeo_index.", call = call)
  }
  if (!is.null(type) && !identical(attr(index, "type"), type)) {
    label <- c(rtree = "an R-tree", kdtree = "a k-d tree")
    zgo_abort(
      NULL,
      sprintf("This query needs %s; the index is %s.", label[[type]], label[[attr(index, "type")]]),
      call = call
    )
  }
}

# Item numbers (1-based, as C returns them) to rows of the indexed vector.
zgo_index_rows <- function(index, items) index$rows[items]

# One query gives its rows, sorted; several give a data frame.
zgo_query_result <- function(index, res, n_queries) {
  rows <- zgo_index_rows(index, res$item)
  if (n_queries == 1L) {
    return(sort(rows))
  }
  out <- data.frame(query = res$query, row = rows)
  out[order(out$query, out$row), , drop = FALSE]
}

zgo_check_query_crs <- function(index, crs, call) {
  if (!geo_crs_equal(attr(index, "crs"), crs) && !is.null(attr(index, "crs")$value)) {
    zgo_abort("crs", "The query's CRS is not the index's.", call = call)
  }
}

#' Query packed indexes
#'
#' `geo_query_box()` finds the indexed geometries whose boxes intersect
#' each query box. `geo_query_radius()` finds the points of a k-d tree
#' within a distance. `geo_query_nearest()` finds up to `k` geometries of
#' an R-tree by box distance, nearest first; a box distance can be smaller
#' than the distance between the geometries, so these are candidates that
#' GEOS or S2 can refine. `geo_join_box()` pairs every box of `y` with the
#' indexed boxes it intersects, in one call; when `y` is itself an R-tree
#' both trees are descended together (design section 6.8).
#'
#' A query of one box or point gives the matching positions as a sorted
#' integer vector; several give a data frame of `query` and `row`.
#'
#' @param index A `zugeo_index`.
#' @param extent A `geo_extent`.
#' @param x,y Query coordinates for `geo_query_radius()` and
#'   `geo_query_nearest()`.
#' @param r The radius.
#' @param k The most neighbours to return.
#' @param max_distance The largest box distance to return.
#' @param lossy As for [geo_box()].
#' @return For `geo_query_box()` and `geo_query_radius()`, an integer vector
#'   or a data frame of `query` and `row`. For `geo_query_nearest()`, a
#'   data frame of `query`, `row` and `distance`. For `geo_join_box()`, a
#'   data frame of `x` (positions in the indexed vector) and `y`.
#' @export
#' @examples
#' x <- geo_points(c(0, 5, 9), c(0, 5, 9))
#' tree <- geo_rtree(x)
#' geo_query_nearest(tree, 4, 4, k = 2)
#' geo_join_box(tree, geo_extent(c(-1, 8), c(-1, 8), c(1, 10), c(1, 10)))
geo_query_box <- function(index, extent) {
  call <- sys.call()
  zgo_check_index(index, NULL, call)
  zgo_check_extent(extent, call)
  zgo_check_query_crs(index, attr(extent, "crs"), call)
  zgo_extent_check_planar(extent, call)
  e <- zgo_extent_parts(extent)
  res <- if (identical(attr(index, "type"), "rtree")) {
    zgo_check(.Call(zgo_c_rtree_search, index$raw, e$xmin, e$ymin, e$xmax, e$ymax), call = call)
  } else {
    zgo_check(.Call(zgo_c_kdtree_query, index$raw, 0L, e$xmin, e$ymin, e$xmax, e$ymax), call = call)
  }
  zgo_query_result(index, res, length(extent))
}

#' @rdname geo_query_box
#' @export
geo_query_radius <- function(index, x, y, r) {
  call <- sys.call()
  zgo_check_index(index, "kdtree", call)
  n <- max(length(x), length(y), length(r))
  res <- zgo_check(.Call(
    zgo_c_kdtree_query, index$raw, 1L, rep_len(as.double(x), n),
    rep_len(as.double(y), n), rep_len(as.double(r), n), rep_len(0, n)
  ), call = call)
  zgo_query_result(index, res, n)
}

#' @rdname geo_query_box
#' @export
geo_query_nearest <- function(index, x, y, k = 1L, max_distance = Inf) {
  call <- sys.call()
  zgo_check_index(index, "rtree", call)
  if (!(is.numeric(k) && length(k) == 1L && !is.na(k) && k >= 1)) {
    zgo_abort(NULL, "`k` must be a number of at least 1.", call = call)
  }
  n <- max(length(x), length(y))
  res <- zgo_check(.Call(
    zgo_c_rtree_nearest, index$raw, rep_len(as.double(x), n), rep_len(as.double(y), n),
    as.double(k), as.double(max_distance)
  ), call = call)
  data.frame(query = res$query, row = zgo_index_rows(index, res$item), distance = res$distance)
}

#' @rdname geo_query_box
#' @export
geo_join_box <- function(index, y, lossy = c("error", "warn", "allow")) {
  call <- sys.call()
  lossy <- zgo_match_arg(lossy)
  zgo_check_index(index, "rtree", call)
  if (inherits(y, "zugeo_index")) {
    zgo_check_index(y, "rtree", call)
    zgo_check_query_crs(index, attr(y, "crs"), call)
    res <- zgo_check(.Call(zgo_c_rtree_join, index$raw, y$raw), call = call)
    out <- data.frame(x = zgo_index_rows(index, res$query), y = zgo_index_rows(y, res$item))
  } else {
    extent <- if (inherits(y, "geo_extent")) y else geo_box(y, lossy = lossy)
    zgo_check_query_crs(index, attr(extent, "crs"), call)
    zgo_extent_check_planar(extent, call)
    e <- zgo_extent_parts(extent)
    res <- zgo_check(.Call(zgo_c_rtree_search, index$raw, e$xmin, e$ymin, e$xmax, e$ymax),
      call = call
    )
    out <- data.frame(x = zgo_index_rows(index, res$item), y = res$query)
  }
  out <- out[order(out$x, out$y), , drop = FALSE]
  rownames(out) <- NULL
  out
}
