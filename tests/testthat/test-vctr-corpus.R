# Stage 2's exit criterion: every corpus file round-trips through
# arrow_read() and arrow_write(), byte for byte in its extension metadata
# and value for value in its coordinates.

test_that("every corpus file round-trips exactly through zuarrow", {
  for (file in names(corpus_manifest())) {
    path <- corpus_path(file)
    df <- zuarrow::arrow_read(path)
    g <- df$geometry
    expect_s3_class(g, "geo_vctr")

    out <- withr::local_tempfile(fileext = ".arrows")
    zuarrow::arrow_write(df, out)
    before <- field_type(path)
    after <- field_type(out)
    for (key in c("extension", "metadata", "storage", "offsets", "union_ids")) {
      expect_identical(after[[key]], before[[key]], label = paste(file, key))
    }
    back <- zuarrow::arrow_read(out)$geometry
    expect_true(
      zuarrow::arrow_equal(zgo_to_array(back), zgo_to_array(g)),
      label = paste(file, "values")
    )
    expect_identical(format(back), format(g), label = file)
    expect_identical(is.na(back), is.na(g), label = file)

    # Reordered with a null, which gathers rows into a new array.
    picked <- g[c(rev(seq_along(g)), NA)]
    again <- round_trip(data.frame(geometry = picked))$geometry
    expect_identical(format(again), format(picked), label = paste(file, "gathered"))
    expect_identical(
      field_type(out)$metadata, before$metadata,
      label = paste(file, "gathered metadata")
    )
  }
})
