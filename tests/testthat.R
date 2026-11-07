# testthat is in Suggests, and CRAN's NOSUGGESTS check runs this file
# without it, so the suite runs only when it is installed (as zuarrow's).

if (requireNamespace("testthat", quietly = TRUE)) {
  library(testthat)
  library(zugeo)

  test_check("zugeo")
}
