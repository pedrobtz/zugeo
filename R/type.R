#' Describe a GeoArrow field
#'
#' Reads what an Arrow schema says about a GeoArrow field: the extension
#' name, its encoding and layout, and its CRS and edges from the extension
#' metadata. Every GeoArrow 0.2 extension name is understood, in both
#' coordinate layouts, with `list` or `large_list` offsets and the view
#' storage types (design section 6.2). A layout the specification forbids
#' is a `zugeo_layout_error`; malformed metadata is a
#' `zugeo_metadata_error`.
#'
#' @param x An Arrow schema, array or stream handle, from zuarrow or
#'   nanoarrow, or a `geo_vctr`. A field with a `geoarrow.*` extension name is described
#'   directly; a struct, such as a stream's schema, has each of its
#'   GeoArrow fields described.
#' @return A `zugeo_type`, a list of `extension`, `encoding` (`"native"`,
#'   `"wkb"`, `"wkt"` or `"box"`), `geometry_type`, `dimensions` (`NA`
#'   when the storage does not fix them), `coord_type` (`"separated"`,
#'   `"interleaved"`, `"mixed"` or `NA`), `offsets` (one entry per list
#'   level, outer first), `storage` (the Arrow format string), `union_ids`,
#'   `crs` (a `zugeo_crs`), `edges` and `metadata` (the extension metadata
#'   exactly as given, or `NA`). For a struct, a named list of them.
#' @export
geo_type_of <- function(x) {
  call <- sys.call()
  schema <- zgo_as_schema(x, call = call)
  out <- .Call(zgo_c_type_of, schema)
  if (!inherits(out, "zgo_failure")) {
    return(zgo_type_new(out, call = call))
  }
  children <- if (identical(out$kind, "none")) {
    .Call(zgo_c_type_of_children, schema)
  }
  if (length(children) == 0L) {
    zgo_check(structure(list(kind = "layout", message = out$message),
      class = "zgo_failure"
    ), call = call)
  }
  lapply(children, function(child) {
    zgo_type_new(zgo_check(child, call = call), call = call)
  })
}

# The one GeoArrow field of `x`, or an error.
zgo_single_type <- function(x, call) {
  type <- geo_type_of(x)
  if (inherits(type, "zugeo_type")) {
    return(type)
  }
  if (length(type) != 1L) {
    zgo_abort(
      NULL,
      sprintf("`x` has %d GeoArrow fields; give one.", length(type)),
      call = call
    )
  }
  type[[1L]]
}

zgo_is_handle <- function(x) {
  inherits(x, c(
    "nanoarrow_schema", "nanoarrow_array", "nanoarrow_array_stream", "geo_vctr"
  ))
}

zgo_as_schema <- function(x, call) {
  if (inherits(x, "geo_vctr")) {
    return(attr(x, "schema"))
  }
  if (inherits(x, "nanoarrow_schema")) {
    return(x)
  }
  if (!zgo_is_handle(x)) {
    zgo_abort(NULL, "`x` must be an Arrow schema, array or stream handle.",
      call = call
    )
  }
  zuarrow::arrow_schema(x)
}

zgo_edges <- c("planar", "spherical", "vincenty", "thomas", "andoyer", "karney")

zgo_type_new <- function(desc, call) {
  meta <- zgo_parse_metadata(desc$metadata, call)
  structure(
    c(desc, list(crs = meta$crs, edges = meta$edges)),
    class = "zugeo_type"
  )
}

# GeoArrow extension metadata (extension-types.md): `crs`, `crs_type` and
# `edges`, parsed by zujson (design D4). Other keys are kept in the raw
# metadata and otherwise ignored.
zgo_parse_metadata <- function(text, call) {
  none <- list(crs = zgo_crs_new(NULL, NA_character_), edges = "planar")
  if (is.na(text) || !nzchar(text)) {
    return(none)
  }
  value <- tryCatch(
    zujson::json_parse(text, simplify = FALSE),
    zujson_error = function(e) {
      zgo_abort(
        "metadata",
        paste0("The extension metadata is not valid JSON: ", conditionMessage(e)),
        call = call
      )
    }
  )
  if (!is.list(value) || (length(value) > 0L && is.null(names(value)))) {
    zgo_abort("metadata", "The extension metadata must be a JSON object.",
      call = call
    )
  }

  crs_type <- value[["crs_type"]]
  if (!is.null(crs_type)) {
    zgo_check_crs_type(crs_type, call)
  }
  crs <- none$crs
  if (!is.null(value[["crs"]])) {
    raw <- value[["crs"]]
    if (is.list(raw) && (length(raw) == 0L || !is.null(names(raw)))) {
      if (!is.null(crs_type) && crs_type != "projjson") {
        zgo_abort(
          "metadata",
          sprintf("`crs` is a JSON object, so it is PROJJSON, not `%s`.", crs_type),
          call = call
        )
      }
      crs <- zgo_crs_new(raw, "projjson")
    } else if (is.character(raw) && length(raw) == 1L) {
      if (identical(crs_type, "projjson")) {
        zgo_abort(
          "metadata",
          "`crs_type` is \"projjson\" but `crs` is a string.",
          call = call
        )
      }
      crs <- zgo_crs_new(raw, if (is.null(crs_type)) NA_character_ else crs_type)
    } else {
      zgo_abort("metadata", "`crs` must be a JSON object, a string or null.",
        call = call
      )
    }
  }

  edges <- value[["edges"]]
  if (is.null(edges)) {
    edges <- "planar"
  } else if (!(is.character(edges) && length(edges) == 1L &&
    edges %in% zgo_edges)) {
    zgo_abort(
      "metadata",
      sprintf(
        "`edges` must be one of %s.",
        paste0("\"", zgo_edges, "\"", collapse = ", ")
      ),
      call = call
    )
  }
  list(crs = crs, edges = edges)
}

#' @export
format.zugeo_type <- function(x, ...) {
  layout <- c(
    x$encoding,
    if (!is.na(x$dimensions)) x$dimensions,
    if (!is.na(x$coord_type)) x$coord_type,
    if (length(x$offsets)) paste(x$offsets, collapse = "/")
  )
  sprintf(
    "<%s %s; crs %s; edges %s>",
    x$extension,
    paste(layout, collapse = ", "),
    if (is.null(x$crs$value)) "none" else if (is.na(x$crs$type)) "untyped" else x$crs$type,
    x$edges
  )
}

#' @export
print.zugeo_type <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  invisible(x)
}
