test_that("the shared object exports R_init_zugeo only", {
  skip_on_cran()
  abi_skip_instrumented()
  exports <- abi_exports()
  expect_identical(setdiff(exports, "R_init_zugeo"), character())
  expect_true("R_init_zugeo" %in% exports)
})

test_that("no exported symbol is a vendored geoarrow-c or nanoarrow name", {
  # GEOARROW_NAMESPACE and NANOARROW_NAMESPACE rename the vendored APIs to
  # ZugeoGeoArrow* and ZugeoNanoarrowArrow*, and hidden visibility keeps
  # even those out of the export table, so loading geoarrow, nanoarrow or
  # zuarrow in the same session cannot clash (design D2).
  skip_on_cran()
  abi_skip_instrumented()
  vendored <- "^(Arrow|GeoArrow|Zugeo|zgo_|ZGO_)"
  expect_identical(grep(vendored, abi_exports(), value = TRUE), character())
})

test_that("no symbol CRAN's compiled-code check reports is referenced", {
  skip_on_cran()
  abi_skip_instrumented()
  imports <- sub("^_+", "", abi_imports())
  # The object calls R's API, so an empty or unparsed listing is a broken
  # tool or pattern, not a clean object. strtod is geoarrow-c's number
  # parser, so its presence also shows the vendored code is linked.
  expect_true("Rf_mkString" %in% imports)
  expect_true("strtod" %in% imports)
  expect_identical(intersect(imports, abi_forbidden), character())
})
