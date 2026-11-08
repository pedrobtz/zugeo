# Writes the seed corpus in tools/fuzz/corpus: one file per geometry type,
# as WKB (first byte 0) and as WKT (first byte 1). Run from the package root
# with zugeo installed: Rscript tools/fuzz/make-corpus.R
wkt <- c(
  "POINT (30 10)", "POINT EMPTY", "POINT Z (1 2 3)", "POINT M (1 2 3)",
  "POINT ZM (1 2 3 4)", "LINESTRING (30 10, 10 30, 40 40)",
  "POLYGON ((35 10, 45 45, 15 40, 10 20, 35 10), (20 30, 35 35, 30 20, 20 30))",
  "MULTIPOINT ((10 40), (40 30))", "MULTILINESTRING ((10 10, 20 20), (40 40, 30 30))",
  "MULTIPOLYGON (((30 20, 45 40, 10 40, 30 20)), ((15 5, 40 10, 10 20, 15 5)))",
  "GEOMETRYCOLLECTION (POINT (40 10), LINESTRING (10 10, 20 20))",
  "LINESTRING (0.01234567890123456 1e-20, 1.7976931348623157e+308 -0)",
  # Nested collections, as deep as geoarrow-c's writers convert (patch 0003
  # refuses past 255 levels when reading).
  paste0(strrep("GEOMETRYCOLLECTION (", 20), "POINT (1 2)", strrep(")", 20))
)
dir <- "tools/fuzz/corpus"
unlink(list.files(dir, full.names = TRUE))
wkb <- zugeo::geo_as_wkb(zugeo::geo_vctr(wkt))
for (i in seq_along(wkt)) {
  writeBin(c(as.raw(0), wkb[[i]]), file.path(dir, sprintf("wkb-%02d", i)))
  writeBin(c(as.raw(1), charToRaw(wkt[[i]])), file.path(dir, sprintf("wkt-%02d", i)))
}
