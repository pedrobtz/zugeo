# Shared by test-lossy.R; at file level there, a shuffled run could use it before it was defined.

edge_types <- c("planar", "spherical", "vincenty", "thomas", "andoyer", "karney")
# Geometries, and whether they have an edge a non-planar type would change.
edge_cases <- list(
  points = list(c("POINT (1 2)", "POINT (3 4)"), FALSE),
  multipoints = list("MULTIPOINT ((1 2), (3 4))", FALSE),
  empties = list(c("LINESTRING EMPTY", "POLYGON EMPTY", "POINT EMPTY"), FALSE),
  nulls = list(c(NA, NA), FALSE),
  linestring = list("LINESTRING (0 0, 1 1)", TRUE),
  polygon = list("POLYGON ((0 0, 1 0, 0 1, 0 0))", TRUE),
  collection = list("GEOMETRYCOLLECTION (POINT (1 2), LINESTRING (0 0, 1 1))", TRUE),
  collection_of_points = list("GEOMETRYCOLLECTION (POINT (1 2), MULTIPOINT ((3 4)))", FALSE)
)
crs_cases <- list(
  none = NULL,
  projjson = '{"type": "GeographicCRS", "name": "WGS 84", "id": {"authority": "EPSG", "code": 4326}}',
  wkt2 = 'GEOGCRS["WGS 84", DATUM["World Geodetic System 1984", ELLIPSOID["WGS 84", 6378137, 298.257223563]], CS[ellipsoidal, 2], AXIS["longitude", east], AXIS["latitude", north], UNIT["degree", 0.0174532925199433]]',
  authority = "OGC:CRS84",
  srid = geo_crs("4326", crs_type = "srid"),
  untyped = "+proj=longlat +datum=WGS84"
)
