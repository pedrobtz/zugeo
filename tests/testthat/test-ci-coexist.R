# zugeo's vendored geoarrow-c and nanoarrow beside zuarrow's nanoarrow and
# the geoarrow and nanoarrow packages' own copies, in one session (design
# D2, Stage 0). None of them is a dependency: this file is left out of the
# package tarball (.Rbuildignore) and runs from the source tree, in CI by
# oracles.yaml.

oracles <- c("zuarrow", "geoarrow", "nanoarrow")

test_that("zugeo, zuarrow, geoarrow and nanoarrow load and work together", {
  for (package in oracles) {
    skip_without_oracle(package)
    loadNamespace(package)
  }

  # Each package calls into its own copy of the C libraries.
  expect_identical(zugeo_info()$nanoarrow, "0.9.0")
  array <- nanoarrow::as_nanoarrow_array(1:3)
  expect_identical(zuarrow::arrow_to_r(array), 1:3)
  vctr <- geoarrow::as_geoarrow_vctr("POINT (0 1)")
  expect_match(format(vctr), "POINT (0 1)", fixed = TRUE)
  expect_identical(zugeo_info()$geoarrow_c, "0.2.0-SNAPSHOT")
})

test_that("no other loaded shared object exports a zugeo name", {
  skip_on_cran()
  abi_skip_instrumented()
  for (package in oracles) {
    skip_without_oracle(package)
    loadNamespace(package)
  }
  # zugeo's internal prefixes (design section 3) must be its own: no other
  # loaded object may export them.
  dlls <- getLoadedDLLs()
  for (name in intersect(names(dlls), oracles)) {
    exports <- abi_exports_of(dlls[[name]][["path"]])
    expect_identical(
      grep("^(zgo_|ZGO_|Zugeo)", exports, value = TRUE),
      character(),
      label = name
    )
  }
})
