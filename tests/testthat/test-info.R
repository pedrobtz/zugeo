test_that("zugeo_info() reports the versions it is built from", {
  info <- zugeo_info()
  expect_named(
    info,
    c("zugeo", "geoarrow_c", "geoarrow_c_commit", "nanoarrow", "geoarrow")
  )
  expect_identical(info$zugeo, as.character(utils::packageVersion("zugeo")))
  expect_identical(info$geoarrow_c, "0.2.0-SNAPSHOT")
  expect_identical(
    info$geoarrow_c_commit,
    "b3db89fec68043ade505fffb62a668043812884a"
  )
  expect_identical(info$nanoarrow, "0.8.0")
  expect_identical(info$geoarrow, "0.2")
})
