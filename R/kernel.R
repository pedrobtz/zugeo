zgo_geometry_labels <- c(
  "point", "linestring", "polygon", "multipoint", "multilinestring",
  "multipolygon", "geometrycollection"
)
zgo_dims_labels <- c("xy", "xyz", "xym", "xyzm")

# One walk over the rows for every per-row kernel.
zgo_info <- function(x, call) {
  zgo_check_vctr(x, call)
  loc <- zgo_locate(x)
  zgo_check(
    .Call(zgo_c_info_kernel, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row),
    call = call
  )
}

#' Bounds, types and counts over the buffers
#'
#' `geo_box()` gives each geometry's bounding box and `geo_box_all()` the
#' one box around them all, both as a [geo_extent()], computed over the
#' coordinate buffers with no R object per geometry (design section 6.7).
#' Z and M ranges come when the geometries have them. A null geometry's
#' box is `NA` and an empty one's `NaN`.
#'
#' Bounds are planar. For a non-planar edge type a planar box can miss an
#' edge that bulges past its vertices or crosses the antimeridian, so on
#' geometries with edges `geo_box()` is a `zugeo_edges_error` unless `lossy`
#' says otherwise.
#'
#' `geo_types()`, `geo_dims()` and `geo_n_coords()` give each geometry's
#' type, dimensions and number of coordinates (`NA` for a null).
#'
#' @param x A `geo_vctr`.
#' @param lossy As for [geo_as_wkb()]: `"error"`, `"warn"` or `"allow"` a
#'   planar box for non-planar edges.
#' @return `geo_box()` and `geo_box_all()`: a `geo_extent`. `geo_types()`,
#'   `geo_dims()`: character vectors. `geo_n_coords()`: an integer vector.
#' @export
#' @examples
#' x <- geo_vctr(c("POINT (1 2)", "LINESTRING Z (0 0 1, 3 4 5)", NA))
#' geo_box(x)
#' geo_box_all(x)
#' geo_types(x)
#' geo_n_coords(x)
geo_box <- function(x, lossy = c("error", "warn", "allow")) {
  call <- sys.call()
  lossy <- zgo_match_arg(lossy)
  info <- zgo_info(x, call)
  zgo_box_from_info(x, info, lossy, call)
}

zgo_box_from_info <- function(x, info, lossy, call) {
  type <- geo_type_of(x)
  if (!identical(type$edges, "planar")) {
    loc <- zgo_locate(x)
    scan <- zgo_check(
      .Call(zgo_c_scan, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row),
      call = call
    )
    if (isTRUE(scan$has_edges)) {
      zgo_lossy(
        lossy, "edges",
        sprintf(
          paste(
            "A planar box can be wrong for \"%s\" edges, which may bulge past",
            "their vertices or cross the antimeridian. Pass `lossy = \"warn\"` or",
            "`\"allow\"` for the planar box anyway."
          ),
          type$edges
        ),
        call = call,
        edges = type$edges
      )
    }
  }
  parts <- info[c("xmin", "ymin", "xmax", "ymax")]
  if (isTRUE(info$any_z)) parts <- c(parts, info[c("zmin", "zmax")])
  if (isTRUE(info$any_m)) parts <- c(parts, info[c("mmin", "mmax")])
  zgo_extent_new(parts, type$crs, type$edges)
}

#' @rdname geo_box
#' @export
geo_box_all <- function(x, lossy = c("error", "warn", "allow")) {
  geo_extent_union(geo_box(x, lossy = zgo_match_arg(lossy)))
}

#' @rdname geo_box
#' @export
geo_types <- function(x) {
  info <- zgo_info(x, sys.call())
  zgo_geometry_labels[info$type]
}

#' @rdname geo_box
#' @export
geo_dims <- function(x) {
  info <- zgo_info(x, sys.call())
  zgo_dims_labels[info$dims]
}

#' @rdname geo_box
#' @export
geo_n_coords <- function(x) {
  zgo_info(x, sys.call())$n_coords
}

#' Hilbert keys and spatial sorting
#'
#' `geo_hilbert()` maps each geometry's box centre onto a 2^16 by 2^16 grid
#' over `extent` and gives its index along the Hilbert curve, with
#' flatbush's arithmetic exactly, so a zugeo sort and a flatbush index agree
#' (design section 6.7). Null and empty geometries have `NA`. `geo_sort()`
#' gives the permutation that orders `x` by key, nulls and empties last,
#' ties in their original order: `x[geo_sort(x)]` is the sorted vector.
#'
#' @param x A `geo_vctr`.
#' @param extent `NULL` for the box around `x`, or a `geo_extent` of length
#'   one. Centres outside it are clamped onto its edge.
#' @param by The sort key; `"hilbert"` is the one there is.
#' @param lossy As for [geo_box()].
#' @return `geo_hilbert()`: a double vector of unsigned 32-bit keys.
#'   `geo_sort()`: an integer permutation.
#' @export
#' @examples
#' x <- geo_points(c(5, 1, 3), c(5, 1, 3))
#' geo_hilbert(x)
#' geo_sort(x)
geo_hilbert <- function(x, extent = NULL, lossy = c("error", "warn", "allow")) {
  call <- sys.call()
  lossy <- zgo_match_arg(lossy)
  boxes <- geo_box(x, lossy = lossy)
  box <- zgo_extent_parts(boxes)
  if (is.null(extent)) {
    extent <- geo_extent_union(boxes)
  } else if (!inherits(extent, "geo_extent") || length(extent) != 1L) {
    zgo_abort(NULL, "`extent` must be a geo_extent of length one.", call = call)
  }
  e <- zgo_extent_parts(extent)
  if (is.na(e$xmin)) {
    return(rep(NA_real_, length(x)))
  }
  zgo_extent_check_planar(extent, call)
  cx <- (box$xmin + box$xmax) / 2
  cy <- (box$ymin + box$ymax) / 2
  .Call(zgo_c_hilbert, cx, cy, c(e$xmin, e$ymin, e$xmax - e$xmin, e$ymax - e$ymin))
}

#' @rdname geo_hilbert
#' @export
geo_sort <- function(x, by = "hilbert", lossy = c("error", "warn", "allow")) {
  by <- zgo_match_arg(by)
  order(geo_hilbert(x, lossy = zgo_match_arg(lossy)), na.last = TRUE, method = "radix")
}

zgo_finding_labels <- c(
  "unclosed_ring", "short_ring", "non_finite", "mixed_dimensions",
  "exterior_clockwise", "interior_counterclockwise", "short_linestring"
)

#' Report what is wrong with geometries, without repairing it
#'
#' One row per finding (design section 6.11), what `gpq validate` checks
#' for geometry values: a ring that does not close (`unclosed_ring`), a
#' ring of fewer than four positions (`short_ring`), a linestring of one
#' position (`short_linestring`), a coordinate that is not finite in a
#' geometry other than an empty point (`non_finite`), parts of different
#' dimensions in one geometry (`mixed_dimensions`), and rings against the
#' RFC 7946 winding convention, exteriors anticlockwise
#' (`exterior_clockwise`, `interior_counterclockwise`), which Simple
#' Features does not require and are reported for information.
#'
#' @param x A `geo_vctr`.
#' @return A data frame of `row` (the element of `x`), `issue`, `part` and
#'   `ring` (`NA` outside a ring); no rows when nothing is wrong.
#' @export
#' @examples
#' geo_validate(geo_vctr(c("POLYGON ((0 0, 1 0, 0 1))", "POINT (1 2)")))
geo_validate <- function(x) {
  call <- sys.call()
  zgo_check_vctr(x, call)
  loc <- zgo_locate(x)
  res <- zgo_check(
    .Call(zgo_c_validate, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row),
    call = call
  )
  data.frame(
    row = res$row,
    issue = zgo_finding_labels[res$code],
    part = res$part,
    ring = res$ring
  )
}
