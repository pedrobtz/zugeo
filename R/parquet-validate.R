# geo_validate_parquet() (design section 6.11): the geo key against the
# GeoParquet schema, against the Parquet schema and native types, against
# the data, and the distribution guide's advice.

# GeoParquet 1 has two edge types; 2 has every GeoArrow one.
zgo_pq_edges <- function(major) {
  if (identical(major, "1")) c("planar", "spherical") else zgo_edges
}

#' Report what is wrong with a GeoParquet file
#'
#' One row per finding (design section 6.11), the checks `gpq validate`
#' makes and those GeoParquet 2.0 adds. Errors break the specification:
#' a missing or malformed `geo` key (`geo_key_missing`, `geo_key_invalid`,
#' `version_invalid`, `primary_column_invalid`, `columns_invalid`,
#' `primary_column_not_in_columns`), a column entry that breaks the schema
#' (`encoding_invalid`, `geometry_types_invalid`, `crs_invalid`,
#' `orientation_invalid`, `edges_invalid`, `bbox_invalid`, `epoch_invalid`),
#' a geometry column that is missing, nested, repeated or not `BYTE_ARRAY`
#' (`column_missing`, `column_grouped`, `column_repeated`,
#' `column_not_byte_array`), a 2.0 column without the native type
#' (`native_type_missing`) or not in the `geo` key (`column_undeclared`),
#' and the `geo` key and native type disagreeing (`crs_mismatch`,
#' `edges_mismatch`, `crs_key_missing`). The data scan adds WKB that does
#' not parse (`wkb_invalid`), types the metadata does not list
#' (`geometry_type_undeclared`), rings against a declared orientation
#' (`orientation_wrong`), geometries outside the `geo` key's `bbox`
#' (`bbox_exceeded`), and row groups whose native statistics miss their
#' data (`statistics_exceeded`, `statistics_types`).
#'
#' Warnings are geometries that are not valid simple features, as
#' [geo_validate()] reports them (winding only where `orientation` is
#' declared), and the advice of the GeoParquet distribution guide that the
#' file shows: compression other than zstd (`not_zstd`), row groups over
#' 200,000 rows (`row_group_large`), and row groups whose boxes overlap so
#' much that the data cannot be spatially ordered (`not_spatially_ordered`).
#' The `crs` is checked to be a JSON object or `null`, not validated
#' against the PROJJSON schema. Needs the qio package.
#'
#' @param path A Parquet file path.
#' @param metadata_only `TRUE` to skip the data scan, as `gpq validate
#'   --metadata-only` does.
#' @return A data frame of `column` (`NA` for the file), `row_group` and
#'   `row` (`NA` when the finding is not about one), `issue`, `severity`
#'   (`"error"` or `"warning"`) and `message`; no rows when nothing is wrong.
#' @seealso [geo_validate()], [geo_parquet_info()]
#' @export
#' @examplesIf requireNamespace("qio", quietly = TRUE) && getNamespaceVersion("qio") >= "0.1.1.9000"
#' path <- tempfile(fileext = ".parquet")
#' geo_write_parquet(geo_points(1:3, 1:3, crs = "OGC:CRS84"), path)
#' geo_validate_parquet(path)
geo_validate_parquet <- function(path, metadata_only = FALSE) {
  call <- sys.call()
  if (
    !(is.logical(metadata_only) &&
      length(metadata_only) == 1L &&
      !is.na(metadata_only))
  ) {
    zgo_abort(NULL, "`metadata_only` must be TRUE or FALSE.", call = call)
  }
  pf <- zgo_pq_open(path, call)
  on.exit(qio::close_parquet(pf), add = TRUE)
  v <- zgo_pq_validator(pf)
  zgo_pq_check_geo_key(v)
  zgo_pq_check_columns(v)
  if (!metadata_only) {
    zgo_pq_check_data(v)
  }
  zgo_pq_check_advice(v)
  f <- v$findings
  if (length(f) == 0L) {
    return(data.frame(
      column = character(),
      row_group = integer(),
      row = integer(),
      issue = character(),
      severity = character(),
      message = character()
    ))
  }
  data.frame(
    column = vapply(f, `[[`, character(1), "column"),
    row_group = vapply(f, `[[`, integer(1), "row_group"),
    row = vapply(f, `[[`, integer(1), "row"),
    issue = vapply(f, `[[`, character(1), "issue"),
    severity = vapply(f, `[[`, character(1), "severity"),
    message = vapply(f, `[[`, character(1), "message")
  )
}

zgo_pq_validator <- function(pf) {
  v <- new.env(parent = emptyenv())
  v$pf <- pf
  v$schema <- qio::schema(pf)
  v$kv <- qio::metadata(pf)
  v$rg <- qio::row_groups(pf)
  v$findings <- list()
  v$geo <- NULL
  v$columns <- list()
  v$major <- NA_character_
  v
}

zgo_pq_find <- function(
  v,
  issue,
  message,
  column = NA_character_,
  row_group = NA_integer_,
  row = NA_integer_,
  severity = "error"
) {
  v$findings[[length(v$findings) + 1L]] <- list(
    column = as.character(column),
    row_group = as.integer(row_group),
    row = as.integer(row),
    issue = issue,
    severity = severity,
    message = message
  )
}

zgo_is_string <- function(x) is.character(x) && length(x) == 1L && !is.na(x)

zgo_is_object <- function(x) {
  is.list(x) && (length(x) == 0L || !is.null(names(x)))
}

zgo_pq_check_geo_key <- function(v) {
  text <- v$kv$value[v$kv$key == "geo"]
  if (length(text) == 0L || is.na(text[[1L]])) {
    zgo_pq_find(v, "geo_key_missing", "The file has no `geo` footer key.")
    return(invisible())
  }
  value <- tryCatch(
    zujson::json_parse(text[[1L]], simplify = FALSE),
    zujson_error = function(e) e
  )
  if (
    inherits(value, "error") || !zgo_is_object(value) || length(value) == 0L
  ) {
    zgo_pq_find(v, "geo_key_invalid", "The `geo` key is not a JSON object.")
    return(invisible())
  }
  v$geo <- value
  if (!zgo_is_string(value$version)) {
    zgo_pq_find(v, "version_invalid", "The `geo` key has no `version` string.")
  } else {
    v$major <- sub("\\..*$", "", value$version)
  }
  if (!zgo_is_string(value$primary_column)) {
    zgo_pq_find(
      v,
      "primary_column_invalid",
      "The `geo` key has no `primary_column` string."
    )
  }
  if (!zgo_is_object(value$columns) || length(value$columns) == 0L) {
    zgo_pq_find(v, "columns_invalid", "The `geo` key has no `columns` object.")
    return(invisible())
  }
  if (
    zgo_is_string(value$primary_column) &&
      !value$primary_column %in% names(value$columns)
  ) {
    zgo_pq_find(
      v,
      "primary_column_not_in_columns",
      sprintf(
        "The primary column `%s` is not in `columns`.",
        value$primary_column
      ),
      column = value$primary_column
    )
  }
  for (name in names(value$columns)) {
    zgo_pq_check_column_meta(v, name, value$columns[[name]])
  }
}

zgo_pq_check_column_meta <- function(v, name, meta) {
  find <- function(issue, message) zgo_pq_find(v, issue, message, column = name)
  if (!zgo_is_object(meta)) {
    find(
      "columns_invalid",
      sprintf("The `geo` key's entry for `%s` is not an object.", name)
    )
    return(invisible())
  }
  major <- v$major
  encodings <- if (
    identical(major, "1") &&
      !identical(sub("^1\\.([0-9]+).*$", "\\1", v$geo$version), "0")
  ) {
    c("WKB", zgo_geoarrow_encodings)
  } else {
    "WKB"
  }
  if (!zgo_is_string(meta$encoding) || !meta$encoding %in% encodings) {
    find(
      "encoding_invalid",
      sprintf("Column `%s` has no valid `encoding`.", name)
    )
  }
  types <- meta$geometry_types
  valid_types <- c(outer(zgo_gp_type_names, zgo_gp_dims_suffix, paste0))
  if (
    !is.list(types) ||
      !all(vapply(types, zgo_is_string, logical(1))) ||
      !all(unlist(types) %in% valid_types) ||
      anyDuplicated(unlist(types))
  ) {
    find(
      "geometry_types_invalid",
      sprintf(
        "Column `%s`'s `geometry_types` is not a list of distinct type names.",
        name
      )
    )
  }
  if (
    "crs" %in%
      names(meta) &&
      !is.null(meta$crs) &&
      !(zgo_is_object(meta$crs) && length(meta$crs) > 0L)
  ) {
    find(
      "crs_invalid",
      sprintf("Column `%s`'s `crs` is neither PROJJSON nor null.", name)
    )
  }
  if (
    "orientation" %in%
      names(meta) &&
      !identical(meta$orientation, "counterclockwise")
  ) {
    find(
      "orientation_invalid",
      sprintf("Column `%s`'s `orientation` must be \"counterclockwise\".", name)
    )
  }
  if ("edges" %in% names(meta)) {
    allowed <- zgo_pq_edges(major)
    if (!zgo_is_string(meta$edges) || !meta$edges %in% allowed) {
      find(
        "edges_invalid",
        sprintf(
          "Column `%s`'s `edges` is not one of %s.",
          name,
          paste0("\"", allowed, "\"", collapse = ", ")
        )
      )
    }
  }
  if ("bbox" %in% names(meta)) {
    bbox <- meta$bbox
    sizes <- if (identical(major, "1")) c(4L, 6L) else c(4L, 6L, 8L)
    if (
      !is.list(bbox) ||
        !length(bbox) %in% sizes ||
        !all(vapply(
          bbox,
          function(b) is.numeric(b) && length(b) == 1L,
          logical(1)
        ))
    ) {
      find(
        "bbox_invalid",
        sprintf(
          "Column `%s`'s `bbox` is not %s numbers.",
          name,
          paste(sizes, collapse = " or ")
        )
      )
    }
  }
  if (
    "epoch" %in%
      names(meta) &&
      !(is.numeric(meta$epoch) && length(meta$epoch) == 1L)
  ) {
    find(
      "epoch_invalid",
      sprintf("Column `%s`'s `epoch` is not a number.", name)
    )
  }
}

# The Parquet side of each geometry column, and the native type against
# the geo key.
zgo_pq_check_columns <- function(v) {
  s <- v$schema
  declared <- if (zgo_is_object(v$geo$columns)) {
    names(v$geo$columns)
  } else {
    character()
  }
  native <- s$path[
    s$logical_type %in% c("GEOMETRY", "GEOGRAPHY") & s$path == s$name
  ]
  if (!is.null(v$geo)) {
    for (name in setdiff(native, declared)) {
      zgo_pq_find(
        v,
        "column_undeclared",
        sprintf(
          "Column `%s` is a %s column the `geo` key does not list.",
          name,
          s$logical_type[s$path == name][[1L]]
        ),
        column = name
      )
    }
  }
  for (name in unique(c(declared, native))) {
    meta <- v$geo$columns[[name]]
    encoding <- if (zgo_is_string(meta$encoding)) meta$encoding else "WKB"
    row <- s[s$path == name, , drop = FALSE]
    if (nrow(row) == 0L) {
      nested <- startsWith(s$path, paste0(name, "."))
      if (!any(nested)) {
        zgo_pq_find(
          v,
          "column_missing",
          sprintf("Column `%s` is not in the file.", name),
          column = name
        )
      } else if (identical(encoding, "WKB")) {
        zgo_pq_find(
          v,
          "column_grouped",
          sprintf("Column `%s` is a group, not WKB.", name),
          column = name
        )
      }
      next
    }
    if (row$repetition_type[[1L]] == "REPEATED") {
      zgo_pq_find(
        v,
        "column_repeated",
        sprintf("Column `%s` is repeated.", name),
        column = name
      )
    }
    if (row$physical_type[[1L]] != "BYTE_ARRAY") {
      zgo_pq_find(
        v,
        "column_not_byte_array",
        sprintf(
          "Column `%s` is %s, not BYTE_ARRAY.",
          name,
          row$physical_type[[1L]]
        ),
        column = name
      )
    }
    logical <- row$logical_type[[1L]]
    if (identical(v$major, "2") && !logical %in% c("GEOMETRY", "GEOGRAPHY")) {
      zgo_pq_find(
        v,
        "native_type_missing",
        sprintf(
          "GeoParquet 2 stores column `%s` as GEOMETRY or GEOGRAPHY.",
          name
        ),
        column = name
      )
    }
    if (!zgo_is_object(meta)) {
      meta <- NULL
    }
    entry <- tryCatch(
      zgo_pq_column(
        name,
        meta,
        row[row$logical_type %in% c("GEOMETRY", "GEOGRAPHY"), , drop = FALSE],
        s,
        v$kv,
        NULL
      ),
      zugeo_error = function(e) e
    )
    if (inherits(entry, "zugeo_error")) {
      if (!is.null(entry$issue) && entry$issue != "edges_invalid") {
        zgo_pq_find(v, entry$issue, conditionMessage(entry), column = name)
      }
    } else {
      v$columns[[name]] <- entry
    }
  }
}

zgo_pq_check_data <- function(v) {
  ends <- cumsum(v$rg$rows)
  stats <- qio::geospatial_statistics(v$pf)
  for (name in names(v$columns)) {
    column <- v$columns[[name]]
    row <- v$schema[v$schema$path == name, , drop = FALSE]
    if (
      !identical(column$encoding, "WKB") ||
        nrow(row) == 0L ||
        row$physical_type[[1L]] != "BYTE_ARRAY"
    ) {
      next
    }
    find <- function(
      issue,
      message,
      row_group = NA_integer_,
      row = NA_integer_,
      severity = "error"
    ) {
      zgo_pq_find(
        v,
        issue,
        message,
        column = name,
        row_group = row_group,
        row = row,
        severity = severity
      )
    }
    wkb <- qio::collect(v$pf, columns = name)[[name]]
    x <- tryCatch(
      {
        g <- geo_vctr(wkb, crs = column$crs, edges = column$edges)
        list(
          g = g,
          types = geo_types(g),
          dims = geo_dims(g),
          box = zgo_extent_parts(geo_box(g, lossy = "allow"))
        )
      },
      # The WKB reader's failure is a plain error from C.
      error = function(e) e
    )
    if (inherits(x, "error")) {
      find(
        "wkb_invalid",
        sprintf(
          "Column `%s` holds WKB that does not parse: %s",
          name,
          conditionMessage(x)
        )
      )
      next
    }
    present <- !is.na(x$types)
    label <- paste0(
      zgo_gp_type_names[match(x$types, zgo_geometry_labels)],
      zgo_gp_dims_suffix[x$dims]
    )
    declared <- column$geometry_types
    if (length(declared)) {
      bad <- which(present & !label %in% declared)
      for (k in zgo_head(bad)) {
        find(
          "geometry_type_undeclared",
          sprintf(
            "Row %d is a %s, which `geometry_types` does not list.",
            k,
            label[[k]]
          ),
          row = k
        )
      }
    }
    findings <- geo_validate(x$g)
    winding <- findings$issue %in%
      c("exterior_clockwise", "interior_counterclockwise")
    meta <- v$geo$columns[[name]]
    if (identical(meta$orientation, "counterclockwise")) {
      for (k in zgo_head(unique(findings$row[winding]))) {
        find(
          "orientation_wrong",
          sprintf(
            "Row %d has a ring against the declared counterclockwise orientation.",
            k
          ),
          row = k
        )
      }
    }
    other <- findings[!winding, , drop = FALSE]
    for (k in zgo_head(seq_len(nrow(other)))) {
      find(
        other$issue[[k]],
        sprintf(
          "Row %d: %s.",
          other$row[[k]],
          gsub("_", " ", other$issue[[k]])
        ),
        row = other$row[[k]],
        severity = "warning"
      )
    }
    box <- x$box
    has <- !is.na(box$xmin)
    b <- column$bbox
    if (length(b) %in% c(4L, 6L, 8L) && any(has)) {
      half <- length(b) / 2L
      x0 <- b[[1L]]
      y0 <- b[[2L]]
      x1 <- b[[half + 1L]]
      y1 <- b[[half + 2L]]
      out_x <- if (x0 <= x1) {
        box$xmin < x0 | box$xmax > x1
      } else {
        (box$xmax > x1 & box$xmax < x0) | (box$xmin < x0 & box$xmin > x1)
      }
      out <- which(has & (out_x | box$ymin < y0 | box$ymax > y1))
      for (k in zgo_head(out)) {
        find(
          "bbox_exceeded",
          sprintf("Row %d extends outside the `geo` key's bbox.", k),
          row = k
        )
      }
    }
    s <- stats[stats$path == name, , drop = FALSE]
    for (i in seq_len(nrow(s))) {
      g <- s$row_group[[i]]
      rows <- seq.int(
        if (g == 1L) 1L else ends[[g - 1L]] + 1L,
        length.out = v$rg$rows[[g]]
      )
      rows <- rows[has[rows]]
      if (
        !is.na(s$xmin[[i]]) &&
          s$xmin[[i]] <= s$xmax[[i]] &&
          length(rows) &&
          (min(box$xmin[rows]) < s$xmin[[i]] ||
            max(box$xmax[rows]) > s$xmax[[i]] ||
            min(box$ymin[rows]) < s$ymin[[i]] ||
            max(box$ymax[rows]) > s$ymax[[i]])
      ) {
        find(
          "statistics_exceeded",
          sprintf(
            "Row group %d's data extends outside its geospatial statistics.",
            g
          ),
          row_group = g
        )
      }
      codes <- s$geometry_types[[i]]
      all_rows <- seq.int(
        if (g == 1L) 1L else ends[[g - 1L]] + 1L,
        length.out = v$rg$rows[[g]]
      )
      got <- unique(label[all_rows][present[all_rows]])
      if (
        length(codes) && length(setdiff(got, zgo_gp_types_from_codes(codes)))
      ) {
        find(
          "statistics_types",
          sprintf("Row group %d holds types its statistics do not list.", g),
          row_group = g
        )
      }
    }
    v$columns[[name]]$data_boxes <- box
  }
}

# At most this many findings of one kind per column, so a bad file gives a
# readable report.
zgo_head <- function(x, n = 10L) x[seq_len(min(length(x), n))]

zgo_pq_check_advice <- function(v) {
  chunks <- qio::column_chunks(v$pf)
  geometry <- names(v$columns)
  codecs <- unique(chunks$compression[chunks$path %in% geometry])
  if (length(codecs) && any(codecs != "ZSTD")) {
    zgo_pq_find(
      v,
      "not_zstd",
      sprintf(
        "Geometry columns are compressed with %s; the guide advises zstd.",
        paste(codecs[codecs != "ZSTD"], collapse = ", ")
      ),
      severity = "warning"
    )
  }
  large <- v$rg$row_group[v$rg$rows > 200000]
  for (g in large) {
    zgo_pq_find(
      v,
      "row_group_large",
      sprintf(
        "Row group %d has %s rows; the guide advises 50,000 to 200,000.",
        g,
        format(v$rg$rows[v$rg$row_group == g], big.mark = ",")
      ),
      row_group = g,
      severity = "warning"
    )
  }
  primary <- if (zgo_is_string(v$geo$primary_column)) {
    v$geo$primary_column
  } else {
    geometry[1L]
  }
  column <- if (length(primary) && !is.na(primary)) v$columns[[primary]]
  n <- nrow(v$rg)
  if (is.null(column) || n < 2L) {
    return(invisible())
  }
  boxes <- zgo_pq_row_group_boxes(v$pf, NULL, column)
  if (anyNA(boxes$xmin) || any(boxes$xmin > boxes$xmax)) {
    return(invisible())
  }
  area <- function(b) (b$xmax - b$xmin) * (b$ymax - b$ymin)
  total <- (max(boxes$xmax) - min(boxes$xmin)) *
    (max(boxes$ymax) - min(boxes$ymin))
  if (total > 0 && sum(area(boxes)) > 0.75 * n * total) {
    zgo_pq_find(
      v,
      "not_spatially_ordered",
      sprintf(
        "The %d row groups' boxes of `%s` cover the whole extent; sort the rows spatially.",
        n,
        primary
      ),
      column = primary,
      severity = "warning"
    )
  }
}
