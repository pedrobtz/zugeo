# Encodings and interchange (design sections 6.3, 6.6 and 6.10).

# GeoArrowType codes from geoarrow-c's geoarrow_type.h.
zgo_type_wkb <- 100001L
zgo_type_wkt <- 100003L
# No extension metadata. Named, because R CMD check's registration check
# fails on a literal NA among .Call() arguments.
zgo_no_metadata <- NA_character_
zgo_geometry_types <- c(
  point = 1L, linestring = 2L, polygon = 3L, multipoint = 4L,
  multilinestring = 5L, multipolygon = 6L
)

# geoarrow-c's GeoArrowMakeType(): native type from geometry type (1-6),
# dimensions (1 XY to 4 XYZM) and layout.
zgo_native_type <- function(geometry_type, dims, layout) {
  (dims - 1L) * 1000L + (if (layout == "interleaved") 10000L else 0L) + geometry_type
}

zgo_check_vctr <- function(x, call) {
  if (!is_geo_vctr(x)) {
    zgo_abort(NULL, "`x` must be a geo_vctr.", call = call)
  }
}


#' Convert geometries between encodings
#'
#' `geo_as_wkb()` gives well-known binary as a list of raw vectors, ISO and
#' little-endian, `NULL` for a null geometry; `sf::st_as_sfc()`,
#' `geos::geos_read_wkb()` and `s2::s2_geog_from_wkb()` each read it
#' directly. `geo_as_wkt()` gives well-known text, with every coordinate
#' written as the shortest text that reads back to the same double, so the
#' round trip is exact. Both carry the CRS as the attribute `crs`, since
#' bare WKB and WKT have no place for one (design section 6.3).
#'
#' `geo_as_native()` gives a `geo_vctr` in a GeoArrow native type. The type
#' is the one the geometries share, a single type promoted to its multi type
#' where both appear; mixed types and geometry collections need WKB or WKT.
#'
#' @param x A `geo_vctr`.
#' @param lossy What to do when the conversion would lose information: a
#'   non-planar edge type on geometries with edges, which WKB and WKT
#'   cannot carry. `"error"` (a `zugeo_edges_error`), `"warn"` (a
#'   `zugeo_edges_warning`) or `"allow"`. The CRS is never lost: it rides
#'   as the `crs` attribute.
#' @param layout `"separated"` (a struct of coordinate arrays, as GeoArrow
#'   advises) or `"interleaved"`.
#' @param type `NULL` to infer, or one of `"point"`, `"linestring"`,
#'   `"polygon"`, `"multipoint"`, `"multilinestring"` and
#'   `"multipolygon"`; needed when every geometry is null.
#' @return `geo_as_wkb()`: a list of raw vectors; `geo_as_wkt()`: a
#'   character vector; `geo_as_native()`: a `geo_vctr`.
#' @seealso [geo_vctr()] for the reverse, [geo_crs_text()].
#' @export
#' @examples
#' x <- geo_vctr(c("POINT (1 2)", "LINESTRING (0 0, 1 1)", NA))
#' geo_as_wkt(x)
#' lengths(geo_as_wkb(x))
geo_as_wkb <- function(x, lossy = c("error", "warn", "allow")) {
  call <- sys.call()
  lossy <- match.arg(lossy)
  zgo_check_vctr(x, call)
  zgo_check_edges_kept(x, lossy, "WKB", call)
  loc <- zgo_locate(x)
  out <- zgo_check(.Call(
    zgo_c_write, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row,
    zgo_type_wkb, zgo_no_metadata, TRUE
  ), call = call)
  attr(out, "crs") <- geo_crs(x)
  out
}

#' @rdname geo_as_wkb
#' @export
geo_as_wkt <- function(x, lossy = c("error", "warn", "allow")) {
  call <- sys.call()
  lossy <- match.arg(lossy)
  zgo_check_vctr(x, call)
  zgo_check_edges_kept(x, lossy, "WKT", call)
  loc <- zgo_locate(x)
  out <- zgo_check(.Call(
    zgo_c_write, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row,
    zgo_type_wkt, zgo_no_metadata, TRUE
  ), call = call)
  attr(out, "crs") <- geo_crs(x)
  out
}

#' @rdname geo_as_wkb
#' @export
geo_as_native <- function(x, layout = c("separated", "interleaved"), type = NULL) {
  call <- sys.call()
  zgo_check_vctr(x, call)
  layout <- match.arg(layout)
  loc <- zgo_locate(x)
  scan <- zgo_check(
    .Call(zgo_c_scan, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row),
    call = call
  )
  geometry_type <- if (is.null(type)) {
    zgo_infer_type(scan$types, call)
  } else {
    if (!(is.character(type) && length(type) == 1L && type %in% names(zgo_geometry_types))) {
      zgo_abort(
        NULL,
        sprintf(
          "`type` must be one of %s.",
          paste0("\"", names(zgo_geometry_types), "\"", collapse = ", ")
        ),
        call = call
      )
    }
    requested <- zgo_geometry_types[[type]]
    # The geometries must already be `type`, or its single type when `type`
    # is a multi type: anything else would be reshaped, not converted.
    if (length(scan$types)) {
      inferred <- zgo_infer_type(scan$types, call)
      if (!(requested == inferred || (inferred <= 3L && requested == inferred + 3L))) {
        zgo_abort(
          "layout",
          sprintf(
            "The geometries are %ss, which `type = \"%s\"` cannot hold without changing them.",
            names(zgo_geometry_types)[inferred], type
          ),
          call = call
        )
      }
    }
    requested
  }
  if (length(scan$dims) > 1L) {
    zgo_abort(
      "layout",
      "The geometries have mixed dimensions; a native type holds one.",
      call = call
    )
  }
  dims <- if (length(scan$dims)) scan$dims else 1L
  code <- zgo_native_type(geometry_type, dims, layout)
  meta <- geo_type_of(x)$metadata
  res <- zgo_check(.Call(
    zgo_c_write, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row,
    as.integer(code), meta, FALSE
  ), call = call)
  zgo_from_array(res$array, res$schema, call = call)
}

# Bare WKB and WKT have no place for an edge type, so non-planar edges are
# lost in them, except where the geometries have no edges: points,
# multipoints, empties (extension-types.md; design section 6.3).
zgo_check_edges_kept <- function(x, lossy, encoding, call) {
  edges <- geo_type_of(x)$edges
  if (identical(edges, "planar")) {
    return(invisible())
  }
  loc <- zgo_locate(x)
  scan <- zgo_check(
    .Call(zgo_c_scan, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row),
    call = call
  )
  if (!isTRUE(scan$has_edges)) {
    return(invisible())
  }
  zgo_lossy(
    lossy, "edges",
    sprintf(
      paste(
        "%s has no place for the \"%s\" edge type, so its lines and rings would",
        "read as planar. Keep the column in Arrow, or pass `lossy = \"warn\"`",
        "or `\"allow\"` to write it anyway."
      ),
      encoding, edges
    ),
    call = call,
    edges = edges
  )
}

# The one native type holding top-level types `types` (1 to 7): a single
# type, or a single type with its multi type promoted to the multi type.
zgo_infer_type <- function(types, call) {
  if (length(types) == 0L) {
    zgo_abort(
      "layout",
      "Every geometry is null, so there is no type to infer; give `type`.",
      call = call
    )
  }
  if (7L %in% types) {
    zgo_abort(
      "layout",
      "Geometry collections have no native type here; keep them as WKB or WKT.",
      call = call
    )
  }
  family <- unique(((types - 1L) %% 3L) + 1L)
  if (length(family) > 1L) {
    zgo_abort(
      "layout",
      paste(
        "The geometries mix points, lines and polygons; a native type holds",
        "one kind. Keep them as WKB or WKT."
      ),
      call = call
    )
  }
  max(types)
}

#' Make geometry vectors from WKB, WKT or Arrow
#'
#' `geo_vctr()` reads well-known binary (a list of raw vectors, such as
#' `sf::st_as_binary()`, `wk::as_wkb()` or `geos::geos_write_wkb()` return),
#' EWKB with an SRID, hex WKB as databases return it, or well-known text.
#' Every element is checked by parsing it. WKB is stored as ISO
#' little-endian WKB; WKT is stored exactly as given.
#'
#' The CRS is `crs` when given, else the input's `crs` attribute (as
#' [geo_as_wkb()] sets), else an EWKB SRID, which becomes a CRS of
#' `crs_type = "srid"`. Elements with differing SRIDs are a
#' `zugeo_crs_error`. A CRS is never looked up or guessed.
#'
#' @param x A list of raw vectors (`NULL` for null), a character vector of
#'   WKT or hex WKB (`NA` for null), an Arrow array handle of a GeoArrow
#'   field, or a `geo_vctr`.
#' @param crs `NULL`, or anything [geo_crs()] takes. Only for WKB and WKT.
#' @param edges `NULL` for planar, or one of `"planar"`, `"spherical"`,
#'   `"vincenty"`, `"thomas"`, `"andoyer"` and `"karney"`. Only for WKB and
#'   WKT.
#' @return A `geo_vctr`.
#' @export
#' @examples
#' geo_vctr(c("POINT (1 2)", NA), crs = "OGC:CRS84")
#' geo_vctr(list(as.raw(c(1, 1, 0, 0, 0, rep(0, 16)))))
#' is_geo_vctr(1)
geo_vctr <- function(x, crs = NULL, edges = NULL) {
  call <- sys.call()
  if (is_geo_vctr(x) || inherits(x, "nanoarrow_array")) {
    if (!is.null(crs) || !is.null(edges)) {
      zgo_abort(
        NULL,
        "`crs` and `edges` apply to WKB and WKT input; an Arrow field carries its own.",
        call = call
      )
    }
    if (is_geo_vctr(x)) {
      return(x)
    }
    return(zgo_from_array(x, zuarrow::arrow_schema(x), call = call))
  }
  edges <- zgo_check_edges(edges, call)
  if (is.logical(x) && all(is.na(x))) {
    x <- as.character(x)
  }
  if (is.character(x)) {
    present <- x[!is.na(x)]
    if (length(present) > 0L && all(grepl("^([0-9A-Fa-f]{2})+$", present))) {
      return(zgo_from_wkb(
        zgo_check(.Call(zgo_c_hex_to_raw, x), call = call),
        attr(x, "crs"), crs, edges, call
      ))
    }
    return(zgo_from_wkt(x, crs, edges, call))
  }
  if (is.list(x) && all(vapply(x, function(e) is.null(e) || is.raw(e), logical(1)))) {
    return(zgo_from_wkb(x, attr(x, "crs"), crs, edges, call))
  }
  zgo_abort(
    NULL,
    "`x` must be a list of raw vectors, a character vector, or an Arrow array handle.",
    call = call
  )
}

#' @rdname geo_vctr
#' @export
is_geo_vctr <- function(x) inherits(x, "geo_vctr")

zgo_check_edges <- function(edges, call) {
  if (is.null(edges)) {
    return("planar")
  }
  if (!(is.character(edges) && length(edges) == 1L && edges %in% zgo_edges)) {
    zgo_abort(
      NULL,
      sprintf("`edges` must be one of %s.", paste0("\"", zgo_edges, "\"", collapse = ", ")),
      call = call
    )
  }
  edges
}

zgo_from_wkb <- function(x, attr_crs, crs, edges, call) {
  res <- zgo_check(.Call(zgo_c_from_wkb, unclass(x)), call = call)
  if (is.null(crs)) {
    srids <- unique(res$srid[!vapply(x, is.null, logical(1))])
    crs <- if (!is.null(attr_crs)) {
      attr_crs
    } else if (length(srids) > 1L) {
      zgo_abort(
        "crs",
        sprintf(
          "The EWKB elements carry differing SRIDs (%s); a column has one CRS.",
          paste(ifelse(is.na(srids), "none", srids), collapse = ", ")
        ),
        call = call
      )
    } else if (length(srids) == 1L && !is.na(srids)) {
      geo_crs(as.character(srids), crs_type = "srid")
    }
  }
  zgo_wrap(res$array, "z", "geoarrow.wkb", geo_crs(crs), edges, call)
}

zgo_from_wkt <- function(x, crs, edges, call) {
  array <- zgo_check(.Call(zgo_c_from_wkt, enc2utf8(as.character(x))), call = call)
  if (is.null(crs)) crs <- attr(x, "crs")
  zgo_wrap(array, "u", "geoarrow.wkt", geo_crs(crs), edges, call)
}

# An array made in C becomes a geo_vctr under a schema of `extension` with
# its CRS and edges in the metadata.
zgo_wrap <- function(array, format, extension, crs, edges, call) {
  meta <- zgo_metadata_json(crs, edges)
  spec <- zgo_spec(format, metadata = c(
    "ARROW:extension:name" = extension,
    if (!is.na(meta)) c("ARROW:extension:metadata" = meta)
  ))
  schema <- zgo_schema(spec)
  .Call(zgo_c_array_set_schema, array, schema)
  zgo_from_array(array, schema, call = call)
}

# GeoArrow extension metadata for a CRS and edges, or NA when there is
# nothing to say ("If all metadata keys are omitted, the
# ARROW:extension:metadata should also be omitted").
zgo_metadata_json <- function(crs, edges) {
  parts <- list()
  if (!is.null(crs$value)) {
    parts$crs <- crs$value
    if (!is.na(crs$type) && crs$type != "projjson") {
      parts$crs_type <- crs$type
    }
  }
  if (!identical(edges, "planar")) {
    parts$edges <- edges
  }
  if (length(parts) == 0L) {
    return(NA_character_)
  }
  zujson::json_write(parts)
}

#' The CRS as one string for other packages
#'
#' PROJJSON as compact JSON, any other CRS exactly as stored, `NA` for none.
#' PROJ reads all of these as user input, so `sf::st_crs(geo_crs_text(x))`
#' takes them (design section 6.4).
#'
#' @param x Anything [geo_crs()] takes.
#' @return A string.
#' @export
#' @examples
#' geo_crs_text(geo_vctr("POINT (1 2)", crs = "OGC:CRS84"))
geo_crs_text <- function(x) {
  crs <- geo_crs(x)
  if (is.null(crs$value)) {
    return(NA_character_)
  }
  if (is.list(crs$value)) {
    return(as.character(zujson::json_write(crs$value)))
  }
  crs$value
}

#' Coordinates as columns
#'
#' `geo_coords()` gives one row per vertex, with the CRS and edge type as
#' the attributes `crs` and `edges`, which `geo_from_coords()` takes back: `x`, `y`, and `z` and `m` when
#' present, with `feature` (the element of `x`), `part` (the simple geometry
#' within a multi-geometry or collection) and `ring` (the polygon ring, `NA`
#' outside polygons). Null and empty geometries have no rows.
#' `geo_from_coords()` is the reverse for one native type, and
#' `geo_points()` makes points straight from vectors (design section 6.10).
#'
#' @param x A `geo_vctr` for `geo_coords()`; x coordinates for
#'   `geo_points()`.
#' @param coords A data frame with `x`, `y`, optionally `z` and `m`, and
#'   `feature`, `part` and `ring` as `geo_coords()` gives them, ordered by
#'   `feature`. `part` and `ring` default to 1.
#' @param type One of `"point"`, `"linestring"`, `"polygon"`,
#'   `"multipoint"`, `"multilinestring"` and `"multipolygon"`.
#' @param n The number of features; by default the largest `feature`.
#'   Features with no rows are empty.
#' @param y,z,m Coordinate vectors; `z` and `m` may be `NULL`.
#' @param crs,edges As for [geo_vctr()]; by default the `crs` and `edges`
#'   attributes of `coords`.
#' @param layout As for [geo_as_native()].
#' @return `geo_coords()`: a data frame; the others: a `geo_vctr`.
#' @export
#' @examples
#' x <- geo_vctr("POLYGON ((0 0, 1 0, 0 1, 0 0))")
#' geo_coords(x)
#' geo_points(1:3, 4:6)
geo_coords <- function(x) {
  call <- sys.call()
  zgo_check_vctr(x, call)
  loc <- zgo_locate(x)
  res <- zgo_check(
    .Call(zgo_c_coords, attr(x, "chunks"), attr(x, "schema"), loc$chunk, loc$row),
    call = call
  )
  out <- as.data.frame(Filter(Negate(is.null), res))
  type <- geo_type_of(x)
  attr(out, "crs") <- type$crs
  attr(out, "edges") <- type$edges
  out
}

#' @rdname geo_coords
#' @export
geo_from_coords <- function(coords, type, n = NULL, crs = NULL, edges = NULL,
                            layout = c("separated", "interleaved")) {
  call <- sys.call()
  layout <- match.arg(layout)
  # The CRS and edges geo_coords() carried, unless given.
  if (is.null(crs)) crs <- attr(coords, "crs")
  if (is.null(edges)) edges <- attr(coords, "edges")
  edges <- zgo_check_edges(edges, call)
  if (!(is.character(type) && length(type) == 1L && type %in% names(zgo_geometry_types))) {
    zgo_abort(NULL, "`type` must name a native geometry type.", call = call)
  }
  if (!is.data.frame(coords) || !all(c("x", "y") %in% names(coords))) {
    zgo_abort(NULL, "`coords` must be a data frame with `x` and `y`.", call = call)
  }
  rows <- nrow(coords)
  # `[[` matches exactly: `$` would read a `mass` column as `m`.
  ints <- function(name, default) {
    v <- coords[[name]]
    if (is.null(v)) rep(default, rows) else as.integer(v)
  }
  feature <- if (is.null(coords[["feature"]]) && type == "point") seq_len(rows) else ints("feature", 1L)
  if (is.null(n)) n <- if (rows) max(feature) else 0L
  dbl <- function(v) if (is.null(v)) NULL else as.double(v)
  z <- dbl(coords[["z"]])
  m <- dbl(coords[["m"]])
  dims <- 1L + (!is.null(z) && is.null(m)) * 1L + (is.null(z) && !is.null(m)) * 2L +
    (!is.null(z) && !is.null(m)) * 3L
  code <- as.integer(zgo_native_type(zgo_geometry_types[[type]], dims, layout))
  array <- zgo_check(.Call(
    zgo_c_from_coords, as.double(coords[["x"]]), as.double(coords[["y"]]), z, m,
    feature, ints("part", 1L), ints("ring", 1L), as.integer(n), zgo_geometry_types[[type]],
    code
  ), call = call)
  meta <- zgo_metadata_json(geo_crs(crs), edges)
  schema <- .Call(zgo_c_type_schema, code, meta)
  .Call(zgo_c_array_set_schema, array, schema)
  zgo_from_array(array, schema, call = call)
}

#' @rdname geo_coords
#' @export
geo_points <- function(x, y, z = NULL, m = NULL, crs = NULL, edges = NULL,
                       layout = c("separated", "interleaved")) {
  coords <- data.frame(x = as.double(x), y = as.double(y))
  if (!is.null(z)) coords$z <- as.double(z)
  if (!is.null(m)) coords$m <- as.double(m)
  geo_from_coords(coords, "point", n = nrow(coords), crs = crs, edges = edges,
    layout = layout
  )
}
