# Every condition zugeo raises inherits from zugeo_error (design section 8).
# `kind` names the subclass: "layout" gives zugeo_layout_error. Extra fields
# (for example `column`) go into the condition object.
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
