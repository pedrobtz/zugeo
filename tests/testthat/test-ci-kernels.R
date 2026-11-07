# Kernels against sf and DuckDB (design section 6.7, Stage 5). Neither is a
# dependency: this file is left out of the package tarball and runs in CI by
# oracles.yaml.

test_that("geo_box() equals sf::st_bbox() per geometry on the corpus", {
  skip_without_oracle("sf")
  for (file in names(corpus_manifest())) {
    g <- zuarrow::arrow_read(corpus_path(file))$geometry
    keep <- !is.na(g) & geo_n_coords(g) > 0L
    if (!any(keep)) next
    sfc <- sf::st_as_sfc(unclass(geo_as_wkb(g[keep])))
    want <- t(vapply(sfc, function(s) as.vector(sf::st_bbox(s)), numeric(4)))
    got <- as.data.frame(geo_box(g[keep]))[c("xmin", "ymin", "xmax", "ymax")]
    expect_equal(unname(as.matrix(got)), unname(want), label = file)
  }
})

test_that("DuckDB's ST_Hilbert agrees with geo_hilbert() over one extent (Q9)", {
  skip_without_oracle("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")
  f <- read.csv(test_path("data", "hilbert-flatbush.csv"))
  wkt <- sprintf("POLYGON ((%.17g %.17g, %.17g %.17g, %.17g %.17g, %.17g %.17g, %.17g %.17g))",
    f$xmin, f$ymin, f$xmax, f$ymin, f$xmax, f$ymax, f$xmin, f$ymax, f$xmin, f$ymin)
  g <- geo_vctr(wkt)
  e <- geo_box_all(g)
  DBI::dbWriteTable(con, "t", data.frame(i = seq_along(wkt), wkt = wkt))
  q <- sprintf(paste(
    "SELECT ST_Hilbert(ST_GeomFromText(wkt), ST_MakeBox2D(ST_Point(%.17g, %.17g),",
    "ST_Point(%.17g, %.17g))) AS h FROM t ORDER BY i"
  ), e$xmin, e$ymin, e$xmax, e$ymax)
  expect_identical(as.double(DBI::dbGetQuery(con, q)$h), geo_hilbert(g))
})
