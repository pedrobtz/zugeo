# Turns a zgo_failure returned by .Call() into its condition; passes any
# other value through. C never raises a zugeo condition itself.
zgo_check <- function(out, call = sys.call(-1), ...) {
  if (inherits(out, "zgo_failure")) {
    zgo_abort(out$kind, out$message, call = call, ...)
  }
  out
}
