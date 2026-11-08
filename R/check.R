# Turns a zgo_failure returned by .Call() into its condition; passes any
# other value through. C never raises a zugeo condition itself.
zgo_check <- function(out, call = sys.call(-1), ...) {
  if (inherits(out, "zgo_failure")) {
    # Kind "" is a plain zugeo_error, with no subclass.
    kind <- if (identical(out$kind, "")) NULL else out$kind
    zgo_abort(kind, out$message, call = call, ...)
  }
  out
}
