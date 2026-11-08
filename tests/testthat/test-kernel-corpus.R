# Stage 5's exit criterion against geoarrow-c: geo_box() equals its box
# kernel on every corpus file it reads (it reads no union or large list,
# design D20), with its Inf/-Inf for nulls and empties.

test_that("geo_box() equals geoarrow-c's box kernel on the corpus", {
  compared <- 0L
  for (file in names(corpus_manifest())) {
    g <- zuarrow::arrow_read(corpus_path(file))$geometry
    chunks <- attr(g, "chunks")
    want <- tryCatch(
      .Call(zgo_c_geoarrow_box, chunks[[1]], attr(g, "schema")),
      error = function(e) NULL
    )
    if (is.null(want)) next
    compared <- compared + 1L
    got <- as.data.frame(geo_box(g))
    empty <- is.na(got$xmin)
    for (k in c("xmin", "ymin", "xmax", "ymax")) {
      expect_identical(got[[k]][!empty], want[[k]][!empty], label = paste(file, k))
    }
    expect_true(all(is.infinite(want$xmin[empty])), label = paste(file, "empties"))
  }
  # geoarrow-c reads every file of the pinned corpus, so none may drop out.
  expect_identical(compared, length(corpus_manifest()))
})

test_that("geo_types() and coordinate counts agree with the corpus", {
  for (file in names(corpus_manifest())) {
    g <- zuarrow::arrow_read(corpus_path(file))$geometry
    type <- geo_type_of(g)
    if (type$encoding == "native") {
      got <- unique(geo_types(g)[!is.na(geo_types(g))])
      expect_identical(got, type$geometry_type, label = file)
    }
    coords <- geo_coords(g)
    counts <- tabulate(coords$feature, nbins = length(g))
    n <- geo_n_coords(g)
    expect_identical(n[!is.na(n)], counts[!is.na(n)], label = file)
  }
})
