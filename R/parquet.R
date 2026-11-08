# GeoParquet over qio (design section 6.9). qio reads and writes the Parquet
# file, the native GEOMETRY and GEOGRAPHY types and their statistics; zugeo
# owns the `geo` key, the CRS and the edges (design Q4).

zgo_qio_version <- "0.1.1.9000"

zgo_need_qio <- function(call) {
  if (
    !requireNamespace("qio", quietly = TRUE) ||
      package_version(getNamespaceVersion("qio")) < zgo_qio_version
  ) {
    zgo_abort(
      NULL,
      "GeoParquet needs the qio package, version 0.1.2 or later.",
      call = call
    )
  }
}

zgo_pq_open <- function(path, call) {
  zgo_need_qio(call)
  if (!(is.character(path) && length(path) == 1L && !is.na(path))) {
    zgo_abort(NULL, "`path` must be a single file path.", call = call)
  }
  qio::open_parquet(path)
}

zgo_geoarrow_encodings <- c(
  "point",
  "linestring",
  "polygon",
  "multipoint",
  "multilinestring",
  "multipolygon"
)

zgo_gp_type_names <- c(
  "Point",
  "LineString",
  "Polygon",
  "MultiPoint",
  "MultiLineString",
  "MultiPolygon",
  "GeometryCollection"
)
zgo_gp_dims_suffix <- c(xy = "", xyz = " Z", xym = " M", xyzm = " ZM")

# GeoParquet geometry type names from ISO WKB codes (1 point, 1001 point Z,
# 2001 point M, 3001 point ZM), as Parquet's statistics record them.
zgo_gp_types_from_codes <- function(codes) {
  codes <- sort(unique(as.integer(codes)))
  base <- codes %% 1000L
  dims <- codes %/% 1000L
  ok <- base >= 1L & base <= 7L & dims >= 0L & dims <= 3L
  paste0(zgo_gp_type_names[base[ok]], zgo_gp_dims_suffix[dims[ok] + 1L])
}

# The GeoParquet geometry types present in a geo_vctr.
zgo_gp_types_of <- function(x) {
  types <- geo_types(x)
  dims <- geo_dims(x)
  keep <- !is.na(types)
  if (!any(keep)) {
    return(character())
  }
  label <- paste0(
    zgo_gp_type_names[match(types[keep], zgo_geometry_labels)],
    zgo_gp_dims_suffix[dims[keep]]
  )
  order <- match(types[keep], zgo_geometry_labels) *
    10L +
    match(dims[keep], names(zgo_gp_dims_suffix))
  unique(label[order(order)])
}

# The native CRS of a GEOMETRY or GEOGRAPHY column, from qio's details
# string, in the forms Parquet's geospatial definitions allow.
zgo_native_crs <- function(text, kv, column, call) {
  if (identical(text, "srid:0")) {
    return(geo_crs(NULL))
  }
  if (startsWith(text, "srid:")) {
    return(geo_crs(sub("^srid:", "", text), crs_type = "srid"))
  }
  if (startsWith(text, "projjson:")) {
    key <- sub("^projjson:", "", text)
    value <- kv$value[kv$key == key]
    if (length(value) == 0L || is.na(value[[1L]])) {
      zgo_abort(
        "metadata",
        sprintf(
          "Column `%s` names its CRS as footer key `%s`, which the file does not have.",
          column,
          key
        ),
        call = call,
        column = column,
        issue = "crs_key_missing"
      )
    }
    crs <- geo_crs(value[[1L]])
    if (!identical(crs$type, "projjson")) {
      zgo_abort(
        "metadata",
        sprintf(
          "Footer key `%s` should hold PROJJSON for column `%s`.",
          key,
          column
        ),
        call = call,
        column = column,
        issue = "crs_key_missing"
      )
    }
    return(crs)
  }
  geo_crs(text)
}

# A geo key's column `crs`: absent is OGC:CRS84, null is none.
zgo_geo_key_crs <- function(meta) {
  if (!("crs" %in% names(meta))) {
    return(geo_crs("OGC:CRS84"))
  }
  value <- meta[["crs"]]
  if (is.null(value)) {
    return(geo_crs(NULL))
  }
  if (is.list(value)) {
    return(zgo_crs_new(value, "projjson"))
  }
  geo_crs(value)
}

# Parse the `geo` footer key, or NULL when there is none.
zgo_pq_geo_key <- function(kv, call) {
  text <- kv$value[kv$key == "geo"]
  if (length(text) == 0L) {
    return(NULL)
  }
  value <- tryCatch(
    zujson::json_parse(text[[1L]], simplify = FALSE),
    zujson_error = function(e) {
      zgo_abort(
        "metadata",
        paste0("The `geo` key is not valid JSON: ", conditionMessage(e)),
        call = call
      )
    }
  )
  if (
    !is.list(value) ||
      is.null(names(value)) ||
      !is.list(value$columns) ||
      (length(value$columns) > 0L && is.null(names(value$columns)))
  ) {
    zgo_abort(
      "metadata",
      "The `geo` key must be a JSON object with a `columns` object.",
      call = call
    )
  }
  value
}

# One description per geometry column: the geo key's columns and the native
# GEOMETRY and GEOGRAPHY columns, the two reconciled.
zgo_pq_describe <- function(pf, call) {
  schema <- qio::schema(pf)
  kv <- qio::metadata(pf)
  geo <- zgo_pq_geo_key(kv, call)
  native <- schema[
    schema$logical_type %in%
      c("GEOMETRY", "GEOGRAPHY") &
      schema$path == schema$name,
    ,
    drop = FALSE
  ]
  names <- unique(c(names(geo$columns), native$path))
  flat <- schema$path[
    schema$path == schema$name & schema$max_repetition_level == 0L
  ]
  columns <- lapply(names, function(name) {
    meta <- geo$columns[[name]]
    row <- native[native$path == name, , drop = FALSE]
    zgo_pq_column(name, meta, row, schema, kv, call)
  })
  names(columns) <- names
  primary <- geo$primary_column
  if (!(is.character(primary) && length(primary) == 1L && primary %in% names)) {
    primary <- if (length(names)) names[[1L]] else NA_character_
  }
  list(
    schema = schema,
    kv = kv,
    geo = geo,
    columns = columns,
    primary = primary,
    flat = flat
  )
}

zgo_pq_column <- function(name, meta, row, schema, kv, call) {
  out <- list(
    name = name,
    in_geo_key = !is.null(meta),
    logical_type = if (nrow(row)) row$logical_type[[1L]] else NA_character_,
    encoding = "WKB",
    crs = NULL,
    edges = "planar",
    geometry_types = NULL,
    bbox = NULL,
    covering = NULL
  )
  native_crs <- NULL
  native_edges <- NULL
  if (nrow(row)) {
    details <- row$logical_details[[1L]]
    algorithm <- NULL
    if (grepl(", algorithm=[A-Z]+$", details)) {
      algorithm <- sub("^.*, algorithm=([A-Z]+)$", "\\1", details)
      details <- sub(", algorithm=[A-Z]+$", "", details)
    }
    native_crs <- zgo_native_crs(sub("^crs=", "", details), kv, name, call)
    native_edges <- if (row$logical_type[[1L]] == "GEOGRAPHY") {
      tolower(algorithm)
    } else {
      "planar"
    }
  }
  if (!is.null(meta)) {
    if (is.character(meta$encoding) && length(meta$encoding) == 1L) {
      out$encoding <- meta$encoding
    }
    if (is.list(meta$geometry_types) || is.character(meta$geometry_types)) {
      out$geometry_types <- as.character(unlist(meta$geometry_types))
    }
    if (is.character(meta$edges) && length(meta$edges) == 1L) {
      out$edges <- meta$edges
    }
    bbox <- unlist(meta$bbox)
    if (is.numeric(bbox) && length(bbox) %in% c(4L, 6L, 8L)) {
      out$bbox <- as.double(bbox)
    }
    out$covering <- meta$covering$bbox
    key_crs <- zgo_geo_key_crs(meta)
    out$crs <- key_crs
    if (!is.null(native_crs)) {
      if (isFALSE(geo_crs_equal(key_crs, native_crs, level = "authority"))) {
        zgo_abort(
          "parquet",
          sprintf(
            "Column `%s` has two CRSs: %s in the `geo` key and %s in its Parquet type.",
            name,
            format(key_crs),
            format(native_crs)
          ),
          call = call,
          column = name,
          issue = "crs_mismatch"
        )
      }
      # The geo key's CRS is complete PROJJSON by the specification; the
      # native one may be a code. Equal by identity, the native is kept.
      if (
        !identical(key_crs$type, "projjson") ||
          geo_crs_equal(key_crs, native_crs)
      ) {
        out$crs <- native_crs
      }
    }
    if (!is.null(native_edges) && !identical(native_edges, out$edges)) {
      zgo_abort(
        "parquet",
        sprintf(
          "Column `%s` has \"%s\" edges in the `geo` key and \"%s\" in its Parquet type.",
          name,
          out$edges,
          native_edges
        ),
        call = call,
        column = name,
        issue = "edges_mismatch"
      )
    }
  } else {
    # Neither the geo key nor a native type: only the validator asks about
    # such a column, and it keeps the planar default.
    out$crs <- native_crs
    if (!is.null(native_edges)) out$edges <- native_edges
  }
  if (!out$edges %in% zgo_edges) {
    zgo_abort(
      "metadata",
      sprintf("Column `%s` has unknown edges \"%s\".", name, out$edges),
      call = call,
      column = name,
      issue = "edges_invalid"
    )
  }
  out
}

zgo_pq_check_wkb <- function(column, call) {
  if (identical(column$encoding, "WKB")) {
    return(invisible())
  }
  if (tolower(column$encoding) %in% zgo_geoarrow_encodings) {
    zgo_abort(
      "parquet",
      sprintf(
        paste(
          "Column `%s` uses GeoParquet 1.1's native \"%s\" encoding, a nested",
          "Parquet column, and qio does not read nested columns yet."
        ),
        column$name,
        column$encoding
      ),
      call = call,
      column = column$name
    )
  }
  zgo_abort(
    "metadata",
    sprintf(
      "Column `%s` has unknown encoding \"%s\".",
      column$name,
      column$encoding
    ),
    call = call,
    column = column$name
  )
}

# Per row group boxes of one column, from the native statistics, else the
# covering column's statistics; NA where neither says.
zgo_pq_row_group_boxes <- function(pf, desc, column) {
  n <- nrow(qio::row_groups(pf))
  out <- data.frame(
    xmin = rep(NA_real_, n),
    ymin = NA_real_,
    xmax = NA_real_,
    ymax = NA_real_
  )
  stats <- qio::geospatial_statistics(pf)
  stats <- stats[stats$path == column$name, , drop = FALSE]
  if (nrow(stats)) {
    out[stats$row_group, c("xmin", "ymin", "xmax", "ymax")] <-
      stats[c("xmin", "ymin", "xmax", "ymax")]
    return(out)
  }
  covering <- column$covering
  if (
    is.list(covering) &&
      all(c("xmin", "ymin", "xmax", "ymax") %in% names(covering))
  ) {
    cs <- qio::column_statistics(pf)
    for (k in c("xmin", "ymin", "xmax", "ymax")) {
      path <- paste(unlist(covering[[k]]), collapse = ".")
      s <- cs[cs$path == path, , drop = FALSE]
      bound <- if (endsWith(k, "min")) s$min else s$max
      ok <- vapply(
        bound,
        function(v) is.numeric(v) && length(v) == 1L,
        logical(1)
      )
      out[[k]][s$row_group[ok]] <- unlist(bound[ok])
    }
  }
  out
}

zgo_pq_query_box <- function(bbox, column, call) {
  if (inherits(bbox, "geo_extent")) {
    if (length(bbox) != 1L) {
      zgo_abort(NULL, "`bbox` must be one box.", call = call)
    }
    crs <- attr(bbox, "crs")
    if (!is.null(crs$value) && !geo_crs_equal(crs, column$crs)) {
      zgo_abort(
        "crs",
        sprintf("`bbox` is not in column `%s`'s CRS.", column$name),
        call = call,
        column = column$name
      )
    }
    p <- zgo_extent_parts(bbox)
    bbox <- c(p$xmin, p$ymin, p$xmax, p$ymax)
  }
  if (
    !(is.numeric(bbox) &&
      length(bbox) == 4L &&
      !anyNA(bbox) &&
      bbox[[1L]] <= bbox[[3L]] &&
      bbox[[2L]] <= bbox[[4L]])
  ) {
    zgo_abort(
      NULL,
      "`bbox` must be a geo_extent or c(xmin, ymin, xmax, ymax) with min <= max.",
      call = call
    )
  }
  as.double(bbox)
}

#' Read and write GeoParquet
#'
#' `geo_read_parquet()` reads a GeoParquet file into a data frame whose
#' geometry columns are `geo_vctr`s, and `geo_write_parquet()` writes one
#' (design section 6.9). Both need the qio package. Other columns go
#' through qio's own mapping.
#'
#' A geometry column is one the `geo` footer key lists or one stored in
#' Parquet's native `GEOMETRY` or `GEOGRAPHY` type; when a file has both,
#' they must agree on the CRS and the edges, or the read is a
#' `zugeo_parquet_error`. A missing CRS in either is OGC:CRS84, as both
#' specifications say, and the CRS `srid:0` or `null` is none. Two
#' statements of a CRS disagree when their authority codes differ or their
#' PROJJSON differs structurally; one that zugeo cannot compare without
#' PROJ is taken on trust, and the geo key's PROJJSON is kept.
#'
#' `bbox` skips the row groups whose box, from the native statistics or
#' else a `covering` column's, misses it, and then keeps the rows whose
#' geometry's box intersects it. That row filter is planar, so on lines
#' and polygons with non-planar edges, which can bulge past their vertices'
#' box, it is a `zugeo_edges_error` unless `lossy` says otherwise, as for
#' [geo_box()]. GeoParquet 1.1's native GeoArrow encodings
#' are nested Parquet columns, which qio does not read yet; such a column
#' is a `zugeo_parquet_error`.
#'
#' `geo_write_parquet()` writes GeoParquet 2.0 by default: WKB in the
#' native `GEOMETRY` type, or `GEOGRAPHY` with its algorithm for non-planar
#' edges, the `geo` key beside it, rows in Hilbert order of the first
#' geometry column, and row groups of `row_group_size` rows. The `geo`
#' key needs every CRS as PROJJSON, OGC:CRS84 or none, because zugeo never
#' resolves a code to its definition; a CRS given as a code or WKT is then
#' written in the Parquet type only, and the `geo` key is left out, as the
#' specification advises for writers that cannot produce PROJJSON. A
#' PROJJSON CRS too long for the Parquet type's 127 bytes is stored under
#' the footer key `projjson_crs_<column>`. `version = "1.1"` writes plain
#' binary with the `geo` key alone, which then must hold the CRS, so a code
#' is a `zugeo_crs_error` there. The `geo` key's `bbox` is written for
#' planar edges only.
#'
#' @param path A Parquet file path.
#' @param bbox `NULL`, a `geo_extent` of length one, or
#'   `c(xmin, ymin, xmax, ymax)`, applied to the primary geometry column.
#' @param columns `NULL` for every column qio reads, or a character vector
#'   of column names.
#' @param lossy For `bbox` over non-planar edges: `"error"`, `"warn"` or
#'   `"allow"` the planar row filter.
#' @param x A data frame with at least one `geo_vctr` column, or a
#'   `geo_vctr`, written as the column `geometry`.
#' @param sort `"hilbert"` to order the rows by [geo_hilbert()] of the first
#'   geometry column, or `"none"`.
#' @param version `"2.0"` or `"1.1"`.
#' @param row_group_size Rows per row group; the GeoParquet distribution
#'   guide suggests 50,000 to 200,000.
#' @param compression As for `qio::write_parquet()`; the guide suggests
#'   zstd.
#' @return `geo_read_parquet()`: a data frame. `geo_write_parquet()`: `path`,
#'   invisibly.
#' @seealso [geo_parquet_info()] for the metadata alone,
#'   [geo_validate_parquet()].
#' @export
#' @examplesIf requireNamespace("qio", quietly = TRUE) && getNamespaceVersion("qio") >= "0.1.1.9000"
#' path <- tempfile(fileext = ".parquet")
#' df <- data.frame(id = 1:3)
#' df$geometry <- geo_points(c(0, 5, 9), c(0, 5, 9), crs = "OGC:CRS84")
#' geo_write_parquet(df, path)
#' geo_read_parquet(path, bbox = c(4, 4, 10, 10))
geo_read_parquet <- function(path, bbox = NULL, columns = NULL,
                             lossy = c("error", "warn", "allow")) {
  call <- sys.call()
  lossy <- match.arg(lossy)
  pf <- zgo_pq_open(path, call)
  on.exit(qio::close_parquet(pf), add = TRUE)
  desc <- zgo_pq_describe(pf, call)
  if (length(desc$columns) == 0L) {
    zgo_abort(
      "parquet",
      "The file has no geometry column: no `geo` key and no GEOMETRY or GEOGRAPHY column.",
      call = call
    )
  }
  if (is.null(columns)) {
    wanted <- unique(c(desc$flat, names(desc$columns)))
  } else {
    if (!(is.character(columns) && !anyNA(columns))) {
      zgo_abort(
        NULL,
        "`columns` must be a character vector of column names.",
        call = call
      )
    }
    wanted <- columns
  }
  geometry <- intersect(wanted, names(desc$columns))
  for (name in geometry) {
    zgo_pq_check_wkb(desc$columns[[name]], call)
  }
  read <- wanted
  groups <- NULL
  primary <- desc$columns[[desc$primary]]
  if (!is.null(bbox)) {
    zgo_pq_check_wkb(primary, call)
    query <- zgo_pq_query_box(bbox, primary, call)
    boxes <- zgo_pq_row_group_boxes(pf, desc, primary)
    miss <- !is.na(boxes$xmin) &
      boxes$xmin <= boxes$xmax &
      (boxes$xmax < query[[1L]] |
        boxes$xmin > query[[3L]] |
        boxes$ymax < query[[2L]] |
        boxes$ymin > query[[4L]])
    groups <- which(!miss)
    read <- unique(c(read, primary$name))
  }
  if (!is.null(groups) && length(groups) == 0L) {
    df <- qio::collect(pf, columns = read, row_groups = 1L)[0L, , drop = FALSE]
  } else {
    df <- qio::collect(pf, columns = read, row_groups = groups)
  }
  for (name in intersect(
    c(geometry, if (!is.null(bbox)) primary$name),
    names(df)
  )) {
    column <- desc$columns[[name]]
    df[[name]] <- geo_vctr(df[[name]], crs = column$crs, edges = column$edges)
  }
  if (!is.null(bbox)) {
    # geo_box()'s edges condition, raised from this call: it is
    # geo_read_parquet()'s `lossy` that the message points to.
    box <- withCallingHandlers(
      zgo_extent_parts(geo_box(df[[primary$name]], lossy = lossy)),
      zugeo_edges_error = function(e) {
        zgo_abort("edges", conditionMessage(e), call = call, edges = e$edges)
      },
      zugeo_edges_warning = function(w) {
        zgo_warn("edges", conditionMessage(w), call = call, edges = w$edges)
        invokeRestart("muffleWarning")
      }
    )
    keep <- !is.na(box$xmin) &
      box$xmin <= query[[3L]] &
      box$xmax >= query[[1L]] &
      box$ymin <= query[[4L]] &
      box$ymax >= query[[2L]]
    df <- df[which(keep), wanted, drop = FALSE]
    rownames(df) <- NULL
  }
  df
}

#' @rdname geo_read_parquet
#' @export
geo_write_parquet <- function(
  x,
  path,
  sort = c("hilbert", "none"),
  version = c("2.0", "1.1"),
  row_group_size = 100000L,
  compression = c("zstd", "snappy", "gzip", "lz4", "uncompressed")
) {
  call <- sys.call()
  zgo_need_qio(call)
  sort <- match.arg(sort)
  version <- match.arg(version)
  compression <- match.arg(compression)
  if (is_geo_vctr(x)) {
    geometry <- x
    x <- data.frame(row.names = seq_along(geometry))
    x$geometry <- geometry
  }
  if (!is.data.frame(x)) {
    zgo_abort(NULL, "`x` must be a data frame or a geo_vctr.", call = call)
  }
  geometry <- names(x)[vapply(x, is_geo_vctr, logical(1))]
  if (length(geometry) == 0L) {
    zgo_abort(NULL, "`x` has no geo_vctr column.", call = call)
  }
  if (sort == "hilbert" && nrow(x) > 1L) {
    x <- x[geo_sort(x[[geometry[[1L]]]], lossy = "allow"), , drop = FALSE]
  }
  plan <- lapply(geometry, function(name) {
    zgo_pq_plan_column(x[[name]], name, version, call)
  })
  names(plan) <- geometry
  geo_key <- all(vapply(plan, function(p) p$in_geo_key, logical(1)))
  if (version == "1.1" && !geo_key) {
    bad <- names(plan)[!vapply(plan, function(p) p$in_geo_key, logical(1))][[
      1L
    ]]
    zgo_abort(
      "crs",
      sprintf(
        paste(
          "GeoParquet 1.1 holds a CRS as PROJJSON only, and column `%s`'s is %s;",
          "zugeo does not resolve codes. Give it a PROJJSON CRS or write version 2.0."
        ),
        bad,
        format(geo_crs(x[[bad]]))
      ),
      call = call,
      column = bad
    )
  }
  footer <- unlist(unname(lapply(plan, function(p) p$footer)))
  if (geo_key) {
    key <- list(
      version = if (version == "2.0") "2.0.0" else "1.1.0",
      primary_column = geometry[[1L]],
      columns = lapply(plan, function(p) p$meta)
    )
    footer <- c(geo = as.character(zujson::json_write(key)), footer)
  }
  for (name in geometry) {
    wkb <- geo_as_wkb(x[[name]], lossy = "allow")
    attributes(wkb) <- NULL
    x[[name]] <- wkb
  }
  schema <- do.call(qio::parquet_schema, lapply(plan, function(p) p$spec))
  qio::write_parquet(
    x,
    path,
    compression = compression,
    schema = schema,
    row_group_size = row_group_size,
    metadata = footer
  )
  invisible(path)
}

# How one geometry column is written: its qio schema entry, its geo key
# entry, whether the geo key can describe it, and any footer entries.
zgo_pq_plan_column <- function(x, name, version, call) {
  type <- geo_type_of(x)
  crs <- type$crs
  edges <- type$edges
  if (version == "1.1" && !edges %in% c("planar", "spherical")) {
    zgo_abort(
      "edges",
      sprintf(
        "GeoParquet 1.1 has planar and spherical edges only, not \"%s\".",
        edges
      ),
      call = call,
      column = name
    )
  }
  meta <- list(encoding = "WKB", geometry_types = as.list(zgo_gp_types_of(x)))
  in_geo_key <- TRUE
  native <- NULL
  footer <- NULL
  if (is.null(crs$value)) {
    meta["crs"] <- list(NULL)
    native <- "srid:0"
  } else if (identical(crs$value, "OGC:CRS84")) {
    native <- "OGC:CRS84"
  } else if (identical(crs$type, "projjson")) {
    meta$crs <- crs$value
    native <- geo_crs_text(crs)
    if (nchar(native, type = "bytes") > 127L) {
      key <- paste0("projjson_crs_", name)
      footer <- structure(native, names = key)
      native <- paste0("projjson:", key)
    }
  } else {
    in_geo_key <- FALSE
    native <- if (identical(crs$type, "srid")) {
      paste0("srid:", crs$value)
    } else {
      crs$value
    }
    if (version == "2.0" && nchar(native, type = "bytes") > 127L) {
      zgo_abort(
        "crs",
        sprintf(
          paste(
            "Column `%s`'s CRS is longer than the 127 bytes a Parquet type holds,",
            "and only PROJJSON can move to the footer. Give it a PROJJSON CRS or a code."
          ),
          name
        ),
        call = call,
        column = name
      )
    }
  }
  if (!identical(edges, "planar")) {
    meta$edges <- edges
  } else {
    box <- zgo_extent_parts(geo_box_all(x))
    if (!is.nan(box$xmin) && !is.na(box$xmin)) {
      meta$bbox <- if (!is.null(box$zmin) && !is.nan(box$zmin)) {
        list(box$xmin, box$ymin, box$zmin, box$xmax, box$ymax, box$zmax)
      } else {
        list(box$xmin, box$ymin, box$xmax, box$ymax)
      }
    }
  }
  spec <- if (version == "1.1") {
    "BINARY"
  } else if (identical(edges, "planar")) {
    list("GEOMETRY", crs = native)
  } else {
    list("GEOGRAPHY", crs = native, algorithm = toupper(edges))
  }
  list(spec = spec, meta = meta, in_geo_key = in_geo_key, footer = footer)
}

#' GeoParquet metadata without reading rows
#'
#' Reads a GeoParquet file's footer and nothing else, as `pyogrio`'s
#' `read_info()` does (design section 6.9, D17): its row count, its row
#' groups, and for each geometry column the encoding, Parquet type,
#' geometry types, CRS, edges, the file's box and each row group's box
#' from the native statistics, or else the `covering` column's. It shows
#' what `bbox` in [geo_read_parquet()] would skip. Needs the qio package.
#'
#' @param path A Parquet file path.
#' @return A `zugeo_parquet_info`: a list of `rows`, `version` (the `geo`
#'   key's, `NA` without one), `primary_column`, `row_groups` (a data frame
#'   of `row_group` and `rows`) and `columns`, one list per geometry column
#'   of `encoding`, `logical_type` (`GEOMETRY`, `GEOGRAPHY`, or `NA` for
#'   plain binary), `geometry_types` (`NULL` when unknown), `crs`, `edges`,
#'   `bbox` (a `geo_extent` of one, from the `geo` key or else the union of
#'   the row groups) and `row_group_bbox` (a `geo_extent` per row group).
#' @export
#' @examplesIf requireNamespace("qio", quietly = TRUE) && getNamespaceVersion("qio") >= "0.1.1.9000"
#' path <- tempfile(fileext = ".parquet")
#' geo_write_parquet(geo_points(1:4, 1:4), path, row_group_size = 2)
#' geo_parquet_info(path)
geo_parquet_info <- function(path) {
  call <- sys.call()
  pf <- zgo_pq_open(path, call)
  on.exit(qio::close_parquet(pf), add = TRUE)
  desc <- zgo_pq_describe(pf, call)
  rg <- qio::row_groups(pf)
  stats <- qio::geospatial_statistics(pf)
  columns <- lapply(desc$columns, function(column) {
    boxes <- zgo_pq_row_group_boxes(pf, desc, column)
    row_group_bbox <- zgo_extent_new(as.list(boxes), column$crs, column$edges)
    types <- column$geometry_types
    if (is.null(types)) {
      codes <- unlist(stats$geometry_types[stats$path == column$name])
      if (length(codes)) types <- zgo_gp_types_from_codes(codes)
    }
    bbox <- if (!is.null(column$bbox)) {
      b <- column$bbox
      half <- length(b) / 2L
      zgo_extent_new(
        list(
          xmin = b[[1L]],
          ymin = b[[2L]],
          xmax = b[[half + 1L]],
          ymax = b[[half + 2L]]
        ),
        column$crs,
        column$edges
      )
    } else if (
      nrow(boxes) && !anyNA(boxes$xmin) && all(boxes$xmin <= boxes$xmax)
    ) {
      geo_extent_union(row_group_bbox)
    } else {
      zgo_extent_new(
        list(
          xmin = NA_real_,
          ymin = NA_real_,
          xmax = NA_real_,
          ymax = NA_real_
        ),
        column$crs,
        column$edges
      )
    }
    list(
      encoding = column$encoding,
      logical_type = column$logical_type,
      geometry_types = types,
      crs = column$crs,
      edges = column$edges,
      bbox = bbox,
      row_group_bbox = row_group_bbox
    )
  })
  version <- desc$geo$version
  structure(
    list(
      rows = sum(rg$rows),
      version = if (is.character(version) && length(version) == 1L) {
        version
      } else {
        NA_character_
      },
      primary_column = desc$primary,
      row_groups = data.frame(row_group = rg$row_group, rows = rg$rows),
      columns = columns
    ),
    class = "zugeo_parquet_info"
  )
}

#' @export
print.zugeo_parquet_info <- function(x, ...) {
  version <- if (is.na(x$version)) {
    "no geo key"
  } else {
    paste("GeoParquet", x$version)
  }
  cat(sprintf(
    "<zugeo_parquet_info: %s rows in %d row groups; %s>\n",
    format(x$rows, big.mark = ","),
    nrow(x$row_groups),
    version
  ))
  for (name in names(x$columns)) {
    col <- x$columns[[name]]
    types <- if (is.null(col$geometry_types)) {
      "types unknown"
    } else if (length(col$geometry_types)) {
      paste(col$geometry_types, collapse = ", ")
    } else {
      "types unknown"
    }
    cat(sprintf(
      "%s %s: %s %s; %s; crs %s; edges %s; bbox %s\n",
      if (identical(name, x$primary_column)) "*" else "-",
      name,
      col$encoding,
      if (is.na(col$logical_type)) "BINARY" else col$logical_type,
      types,
      sub("^<zugeo_crs:? ?(.*)>$", "\\1", format(col$crs)),
      col$edges,
      format(col$bbox)
    ))
  }
  invisible(x)
}
