test_that("every condition inherits from zugeo_error", {
  err <- tryCatch(
    zgo_abort("layout", "bad layout", column = "geom"),
    error = identity
  )
  expect_s3_class(err, c("zugeo_layout_error", "zugeo_error", "error"))
  expect_identical(conditionMessage(err), "bad layout")
  expect_identical(err$column, "geom")

  root <- tryCatch(zgo_abort(NULL, "plain"), error = identity)
  expect_identical(class(root), c("zugeo_error", "error", "condition"))
})
