#' Coordinate reference systems, carried exactly
#'
#' `geo_crs()` returns the CRS of a GeoArrow field, or makes one from a
#' string. zugeo stores a CRS exactly as given, tagged with its GeoArrow
#' `crs_type`, and never resolves or transforms it (design section 6.4).
#'
#' A string is classified as GeoArrow asks: a JSON object is PROJJSON, a
#' string starting with a WKT2 keyword is `"wkt2:2019"`, one of the form
#' `AUTHORITY:CODE` is `"authority_code"`, and anything else has no
#' `crs_type`. `crs_type` overrides the classification.
#'
#' @param x A string, `NULL` or `NA` (no CRS), a `zugeo_crs`, a
#'   `zugeo_type` from [geo_type_of()], or an Arrow schema, array or stream
#'   handle with one GeoArrow field.
#' @param crs_type `NULL` to classify a string, or one of `"projjson"`,
#'   `"wkt2:2019"`, `"authority_code"` and `"srid"`.
#' @return A `zugeo_crs`: a list of `value` (`NULL`, a string, or the
#'   parsed PROJJSON object) and `type` (a `crs_type`, or `NA`).
#' @seealso [geo_crs_equal()]
#' @export
#' @examples
#' geo_crs("OGC:CRS84")
#' geo_crs(NULL)
geo_crs <- function(x, crs_type = NULL) {
  if (inherits(x, "zugeo_crs")) {
    return(x)
  }
  if (inherits(x, "zugeo_type")) {
    return(x$crs)
  }
  if (is.null(x) || (is.atomic(x) && length(x) == 1L && is.na(x))) {
    return(zgo_crs_new(NULL, NA_character_))
  }
  if (is.character(x) && length(x) == 1L) {
    return(zgo_crs_from_text(x, crs_type, call = sys.call()))
  }
  if (zgo_is_handle(x)) {
    return(zgo_single_type(x, call = sys.call())$crs)
  }
  zgo_abort(
    NULL,
    "`x` must be a string, NULL, a zugeo_crs, a zugeo_type or an Arrow handle.",
    call = sys.call()
  )
}

zgo_crs_types <- c("projjson", "wkt2:2019", "authority_code", "srid")

zgo_crs_new <- function(value, type) {
  structure(list(value = value, type = type), class = "zugeo_crs")
}

zgo_wkt2_keywords <- c(
  "GEODCRS", "GEODETICCRS", "GEOGCRS", "GEOGRAPHICCRS", "PROJCRS",
  "PROJECTEDCRS", "VERTCRS", "VERTICALCRS", "ENGCRS", "ENGINEERINGCRS",
  "PARAMETRICCRS", "TIMECRS", "TEMPORALCRS", "DERIVEDPROJCRS", "COMPOUNDCRS",
  "BOUNDCRS"
)

zgo_authority_pattern <- "^[A-Za-z][A-Za-z0-9_.-]*:[A-Za-z0-9_.-]+$"

zgo_crs_from_text <- function(text, crs_type = NULL, call = NULL) {
  if (!is.null(crs_type)) {
    zgo_check_crs_type(crs_type, call)
  }
  trimmed <- trimws(text)
  if (startsWith(trimmed, "{")) {
    value <- tryCatch(
      zujson::json_parse(trimmed, simplify = FALSE),
      zujson_error = function(e) NULL
    )
    if (is.list(value) && !is.null(names(value))) {
      if (!is.null(crs_type) && crs_type != "projjson") {
        zgo_abort(
          "metadata",
          sprintf("A JSON object CRS is PROJJSON, not `%s`.", crs_type),
          call = call
        )
      }
      return(zgo_crs_new(value, "projjson"))
    }
  }
  if (is.null(crs_type)) {
    keyword <- toupper(sub("^([A-Za-z]+)\\s*\\[.*$", "\\1", trimmed))
    crs_type <- if (grepl("[", trimmed, fixed = TRUE) &&
      keyword %in% zgo_wkt2_keywords) {
      "wkt2:2019"
    } else if (grepl(zgo_authority_pattern, trimmed)) {
      "authority_code"
    } else {
      NA_character_
    }
  } else if (crs_type == "projjson") {
    zgo_abort(
      "metadata",
      "A PROJJSON CRS must be a JSON object.",
      call = call
    )
  }
  zgo_crs_new(text, crs_type)
}

zgo_check_crs_type <- function(crs_type, call) {
  if (!(is.character(crs_type) && length(crs_type) == 1L &&
    crs_type %in% zgo_crs_types)) {
    zgo_abort(
      "metadata",
      sprintf(
        "`crs_type` must be one of %s.",
        paste0("\"", zgo_crs_types, "\"", collapse = ", ")
      ),
      call = call
    )
  }
}

#' @export
format.zugeo_crs <- function(x, ...) {
  value <- x$value
  if (is.null(value)) {
    return("<zugeo_crs: none>")
  }
  label <- if (is.list(value)) {
    name <- value[["name"]]
    if (is.character(name) && length(name) == 1L) name else "PROJJSON"
  } else if (nchar(value) > 40L) {
    paste0(substr(value, 1L, 37L), "...")
  } else {
    value
  }
  type <- if (is.na(x$type)) "untyped" else x$type
  sprintf("<zugeo_crs %s: %s>", type, label)
}

#' @export
print.zugeo_crs <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  invisible(x)
}

#' Compare two coordinate reference systems without PROJ
#'
#' Three levels, each looser than the last, after `pyproj`'s
#' `is_exact_same()` and `equals()` (design section 6.4, D14):
#'
#' * `"identical"`: both absent, the same string byte for byte, or the same
#'   PROJJSON object ignoring key order. zugeo's own checks use this level.
#' * `"structural"`: PROJJSON compared after dropping members that do not
#'   change coordinates (`$schema`, `name`, `remarks`, `usages`, `scope`,
#'   `area`, `bbox`) and treating integers and doubles alike. A string CRS
#'   that is not identical gives `NA`.
#' * `"authority"`: the same authority and code, from an `AUTHORITY:CODE`
#'   string or a PROJJSON `id`, with the authority's case ignored and the
#'   pairs that differ only in axis order (`OGC:CRS84` and `EPSG:4326`)
#'   treated as one. A side with no authority and code gives `NA`.
#'
#' `NA` means zugeo cannot tell without PROJ, never that the two differ.
#'
#' @param x,y Anything [geo_crs()] takes.
#' @param level One of `"identical"`, `"structural"` and `"authority"`.
#' @return `TRUE`, `FALSE` or `NA`.
#' @export
#' @examples
#' geo_crs_equal("EPSG:4326", "EPSG:4326")
#' geo_crs_equal("OGC:CRS84", "EPSG:4326")
#' geo_crs_equal("OGC:CRS84", "EPSG:4326", level = "authority")
geo_crs_equal <- function(x, y, level = c("identical", "structural", "authority")) {
  level <- match.arg(level)
  x <- geo_crs(x)
  y <- geo_crs(y)
  a <- x$value
  b <- y$value
  if (is.null(a) || is.null(b)) {
    return(is.null(a) && is.null(b))
  }
  if (zgo_crs_identical(a, b)) {
    return(TRUE)
  }
  if (level == "identical") {
    return(FALSE)
  }
  structural <- if (is.list(a) && is.list(b)) {
    identical(zgo_crs_structure(a), zgo_crs_structure(b))
  } else {
    NA
  }
  if (level == "structural" || isTRUE(structural)) {
    return(structural)
  }
  codes_x <- zgo_crs_codes(x)
  codes_y <- zgo_crs_codes(y)
  if (length(codes_x) == 0L || length(codes_y) == 0L) {
    return(NA)
  }
  any(codes_x %in% codes_y)
}

zgo_crs_identical <- function(a, b) {
  if (is.list(a) != is.list(b)) {
    return(FALSE)
  }
  if (!is.list(a)) {
    return(identical(a, b))
  }
  identical(zgo_canonical(a), zgo_canonical(b))
}

# Key order is not part of a JSON object's value; array order is.
zgo_canonical <- function(x) {
  if (!is.list(x)) {
    return(x)
  }
  if (!is.null(names(x))) {
    x <- x[order(names(x), method = "radix")]
  }
  x[] <- lapply(x, zgo_canonical)
  x
}

zgo_crs_ignored <- c(
  "$schema", "name", "remarks", "usage", "usages", "scope", "area", "bbox"
)

zgo_crs_structure <- function(x) {
  if (is.list(x)) {
    if (!is.null(names(x))) {
      x <- x[!(names(x) %in% zgo_crs_ignored)]
      x <- x[order(names(x), method = "radix")]
    }
    x[] <- lapply(x, zgo_crs_structure)
    return(x)
  }
  if (is.integer(x)) as.double(x) else x
}

# Authority codes differing only in axis order, which cannot differ inside
# GeoArrow (axis order is always longitude, latitude).
zgo_crs_aliases <- c(
  "OGC:CRS84" = "EPSG:4326",
  "OGC:CRS83" = "EPSG:4269",
  "OGC:CRS27" = "EPSG:4267"
)

zgo_crs_codes <- function(crs) {
  value <- crs$value
  codes <- character()
  if (is.list(value)) {
    ids <- c(list(value[["id"]]), value[["ids"]])
    for (id in ids) {
      if (is.list(id) && !is.null(id[["authority"]]) && !is.null(id[["code"]])) {
        codes <- c(codes, paste0(id[["authority"]], ":", id[["code"]]))
      }
    }
  } else if (!identical(crs$type, "srid") &&
    grepl(zgo_authority_pattern, trimws(value))) {
    codes <- trimws(value)
  }
  if (length(codes) == 0L) {
    return(character())
  }
  authority <- toupper(sub(":.*$", "", codes))
  codes <- paste0(authority, ":", sub("^[^:]*:", "", codes))
  aliased <- zgo_crs_aliases[codes]
  unique(ifelse(is.na(aliased), codes, aliased))
}
