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
  # tool or pattern, not a clean object. Rf_allocVector, as zuarrow's test
  # checks on every platform; Rf_mkString was absent from the Windows
  # listing. (Not strtod: under LTO the vendored parser is dropped until
  # something calls it.)
  expect_true(
    "Rf_allocVector" %in% imports,
    label = paste("imports include Rf_allocVector:", paste(head(imports, 20), collapse = " "))
  )
  expect_identical(intersect(imports, abi_forbidden), character())
})
