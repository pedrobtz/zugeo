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
