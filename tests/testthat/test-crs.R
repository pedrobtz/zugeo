
test_that("strings are classified as GeoArrow asks, never guessed further", {
  expect_identical(geo_crs(wgs84)$type, "projjson")
  expect_identical(geo_crs(wkt2)$type, "wkt2:2019")
  expect_identical(geo_crs("EPSG:4326")$type, "authority_code")
  expect_identical(geo_crs("OGC:CRS84")$type, "authority_code")
  expect_identical(geo_crs("4326")$type, NA_character_)
  expect_identical(geo_crs("+proj=longlat +datum=WGS84")$type, NA_character_)
  expect_identical(geo_crs('GEOGCS["WGS 84"]')$type, NA_character_)
  expect_identical(geo_crs("4326", crs_type = "srid")$type, "srid")
  expect_identical(geo_crs("{not json")$type, NA_character_)
  expect_null(geo_crs(NULL)$value)
  expect_null(geo_crs(NA)$value)
  expect_error(geo_crs("x", crs_type = "epsg"), class = "zugeo_metadata_error")
  expect_error(geo_crs("x", crs_type = "projjson"), class = "zugeo_metadata_error")
  expect_error(geo_crs(wgs84, crs_type = "wkt2:2019"), class = "zugeo_metadata_error")
  expect_error(geo_crs(1), class = "zugeo_error")
})

test_that("a CRS reads from a type and a schema handle", {
  s <- ga_schema("point", metadata = '{"crs": "OGC:CRS84"}')
  expect_identical(geo_crs(s)$value, "OGC:CRS84")
  expect_identical(geo_crs(geo_type_of(s))$value, "OGC:CRS84")
  crs <- geo_crs("EPSG:4326")
  expect_identical(geo_crs(crs), crs)
})

test_that("CRS pairs give each level's expected answer", {
  # x, y, identical, structural, authority
  pairs <- list(
    list(NULL, NULL, TRUE, TRUE, TRUE),
    list(NULL, "EPSG:4326", FALSE, FALSE, FALSE),
    list("EPSG:4326", "EPSG:4326", TRUE, TRUE, TRUE),
    list("EPSG:4326", "epsg:4326", FALSE, NA, TRUE),
    list("OGC:CRS84", "EPSG:4326", FALSE, NA, TRUE),
    list("EPSG:4326", "EPSG:3857", FALSE, NA, FALSE),
    list(wgs84, wgs84_reordered, TRUE, TRUE, TRUE),
    list(wgs84, wgs84_renamed, FALSE, TRUE, TRUE),
    list(wgs84, "EPSG:4326", FALSE, NA, TRUE),
    list(wgs84, "OGC:CRS84", FALSE, NA, TRUE),
    list(wgs84_anonymous, "EPSG:4326", FALSE, NA, NA),
    list(wgs84, nad83, FALSE, FALSE, FALSE),
    list(wkt2, wkt2, TRUE, TRUE, TRUE),
    list(wkt2, wkt2_other, FALSE, NA, NA),
    list(geo_crs("4326", crs_type = "srid"), "EPSG:4326", FALSE, NA, NA)
  )
  levels <- c("identical", "structural", "authority")
  for (i in seq_along(pairs)) {
    p <- pairs[[i]]
    for (k in seq_along(levels)) {
      expect_identical(
        geo_crs_equal(p[[1]], p[[2]], levels[[k]]),
        p[[k + 2]],
        label = sprintf("pair %d at level %s", i, levels[[k]])
      )
      # Equality is symmetric.
      expect_identical(
        geo_crs_equal(p[[2]], p[[1]], levels[[k]]),
        p[[k + 2]],
        label = sprintf("pair %d reversed at level %s", i, levels[[k]])
      )
    }
  }
})

test_that("format() names the CRS", {
  expect_identical(format(geo_crs(NULL)), "<zugeo_crs: none>")
  expect_identical(format(geo_crs("EPSG:4326")), "<zugeo_crs authority_code: EPSG:4326>")
  expect_identical(format(geo_crs(wgs84)), "<zugeo_crs projjson: WGS 84>")
  expect_identical(format(geo_crs("4326")), "<zugeo_crs untyped: 4326>")
  expect_match(format(geo_crs(wkt2)), "^<zugeo_crs wkt2:2019: GEOGCRS.*[.][.][.]>$")
  expect_output(print(geo_crs(NULL)), "none")
})
