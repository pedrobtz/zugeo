# Every condition zugeo raises inherits from zugeo_error (design section 8).
# `kind` names the subclass: "layout" gives zugeo_layout_error. Extra fields
# (for example `column`) go into the condition object.
zgo_warn <- function(kind, message, call = NULL, ...) {
  class <- c(
    if (!is.null(kind)) paste0("zugeo_", kind, "_warning"),
    "zugeo_warning",
    "warning",
    "condition"
  )
  warning(structure(
    class = class,
    list(message = message, call = call, ...)
  ))
}

zgo_lossy_policies <- c("error", "warn", "allow")

# One lossy case under the caller's policy (design section 6.3), the same
# three zuarrow's `lossy` takes: an error, a warning, or nothing.
zgo_lossy <- function(lossy, kind, message, call, ...) {
  switch(lossy,
    error = zgo_abort(kind, message, call = call, ...),
    warn = zgo_warn(kind, message, call = call, ...),
    allow = invisible()
  )
}

zgo_abort <- function(kind, message, call = NULL, ...) {
  class <- c(
    if (!is.null(kind)) paste0("zugeo_", kind, "_error"),
    "zugeo_error",
    "error",
    "condition"
  )
  stop(structure(
    class = class,
    list(message = message, call = call, ...)
  ))
}

# match.arg() for zugeo: the choices come from the caller's formals, as
# match.arg() takes them, but a bad value is a zugeo_error (design section
# 8) and there is no partial matching, so `lossy = "w"` is refused rather
# than read as "warn".
zgo_match_arg <- function(arg) {
  parent <- sys.parent()
  name <- as.character(substitute(arg))
  choices <- eval(formals(sys.function(parent))[[name]], envir = sys.frame(parent))
  if (identical(arg, choices)) {
    return(choices[[1L]])
  }
  if (is.character(arg) && length(arg) == 1L && !is.na(arg) && arg %in% choices) {
    return(arg)
  }
  zgo_abort(
    NULL,
    sprintf("`%s` must be one of %s.", name, paste0("\"", choices, "\"", collapse = ", ")),
    call = sys.call(parent)
  )
}
