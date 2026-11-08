# GeoParquet test cases (design section 6.9), shared by test-parquet.R and
# the oracle tests, which hand the same files to DuckDB, GDAL and gpq.

skip_without_qio <- function() {
  skip_if_not_installed("qio", "0.1.1.9000")
}

# OGC:CRS84 as PROJJSON, from the GeoParquet 2.0 specification; longer than
# the 127 bytes a Parquet type holds, so it goes to a footer key.
crs84_projjson <- paste0(
  '{"$schema":"https://proj.org/schemas/v0.5/projjson.schema.json",',
  '"type":"GeographicCRS","name":"WGS 84 longitude-latitude",',
  '"datum":{"type":"GeodeticReferenceFrame","name":"World Geodetic System 1984",',
  '"ellipsoid":{"name":"WGS 84","semi_major_axis":6378137,',
  '"inverse_flattening":298.257223563}},',
  '"coordinate_system":{"subtype":"ellipsoidal","axis":[',
  '{"name":"Geodetic longitude","abbreviation":"Lon","direction":"east","unit":"degree"},',
  '{"name":"Geodetic latitude","abbreviation":"Lat","direction":"north","unit":"degree"}]},',
  '"id":{"authority":"OGC","code":"CRS84"}}'
)

parquet_cases <- function() {
  withr::local_seed(7)
  n <- 1000L
  many <- data.frame(id = seq_len(n), value = stats::runif(n))
  many$geometry <- geo_points(
    stats::runif(n, -180, 180),
    stats::runif(n, -90, 90),
    crs = "OGC:CRS84"
  )
  points <- data.frame(id = 1:4, name = c("a", "b", NA, "d"))
  points$geometry <- geo_vctr(
    c("POINT (1 2)", "POINT (-73.429673 45.008308)", NA, "POINT EMPTY"),
    crs = "OGC:CRS84"
  )
  mixed <- data.frame(id = 1:5)
  mixed$geometry <- geo_vctr(
    c(
      "LINESTRING Z (0 0 1, 1 1 2, 2 0 3)",
      "POLYGON Z ((0 0 0, 4 0 0, 4 4 1, 0 4 1, 0 0 0), (1 1 0, 1 2 0, 2 2 0, 1 1 0))",
      "MULTIPOLYGON Z (((10 10 0, 11 10 0, 11 11 0, 10 10 0)))",
      NA,
      "MULTILINESTRING Z ((5 5 5, 6 6 6))"
    ),
    crs = crs84_projjson
  )
  collection <- data.frame(id = 1:3)
  collection$geometry <- geo_vctr(c(
    "GEOMETRYCOLLECTION (POINT (1 1), LINESTRING (0 0, 0.1 0.2))",
    "MULTIPOINT ((0 0), (1e-300 5e-324))",
    "POLYGON ((0.1 0.1, 0.30000000000000004 0.1, 0.1 0.7, 0.1 0.1))"
  ))
  projected <- data.frame(id = 1:2)
  projected$geometry <- geo_vctr(
    c("POINT (500000 4500000)", "POINT (600000 4600000)"),
    crs = "EPSG:3857"
  )
  routes <- data.frame(id = 1:2)
  routes$geometry <- geo_vctr(
    c("LINESTRING (-170 10, 170 10)", "LINESTRING (0 0, 10 10)"),
    crs = "OGC:CRS84",
    edges = "spherical"
  )
  list(
    points = list(x = points),
    many = list(x = many, args = list(row_group_size = 100L)),
    mixed_z = list(x = mixed),
    no_crs = list(x = collection),
    code_crs = list(x = projected),
    spherical = list(x = routes),
    points_1.1 = list(x = points, args = list(version = "1.1")),
    no_crs_1.1 = list(
      x = collection,
      args = list(version = "1.1", sort = "none")
    )
  )
}

# Writes every case into `dir`; returns the paths, named by case.
write_parquet_cases <- function(dir) {
  cases <- parquet_cases()
  paths <- file.path(dir, paste0(names(cases), ".parquet"))
  names(paths) <- names(cases)
  for (name in names(cases)) {
    case <- cases[[name]]
    do.call(geo_write_parquet, c(list(case$x, paths[[name]]), case$args))
  }
  paths
}

# What qio reads back of a file's footer.
parquet_footer <- function(path) {
  pf <- qio::open_parquet(path)
  on.exit(qio::close_parquet(pf))
  kv <- qio::metadata(pf)
  list(
    schema = qio::schema(pf),
    kv = kv,
    geo = if ("geo" %in% kv$key) {
      zujson::json_parse(kv$value[kv$key == "geo"][[1L]], simplify = FALSE)
    }
  )
}

# Writes a file through qio directly, for footers zugeo would not write.
write_raw_parquet <- function(
  df,
  path,
  schema = NULL,
  geo = NULL,
  extra = NULL
) {
  metadata <- c(if (!is.null(geo)) c(geo = geo), extra)
  qio::write_parquet(df, path, schema = schema, metadata = metadata)
  path
}

wkb_list <- function(wkt) {
  out <- geo_as_wkb(geo_vctr(wkt))
  attributes(out) <- NULL
  out
}
