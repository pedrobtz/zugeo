# Shared by test-crs.R; at file level there, a shuffled run could use it before it was defined.

wgs84 <- '{"$schema": "https://proj.org/schemas/v0.7/projjson.schema.json", "type": "GeographicCRS", "name": "WGS 84", "datum": {"type": "GeodeticReferenceFrame", "name": "World Geodetic System 1984", "ellipsoid": {"name": "WGS 84", "semi_major_axis": 6378137, "inverse_flattening": 298.257223563}}, "coordinate_system": {"subtype": "ellipsoidal", "axis": [{"name": "Longitude", "abbreviation": "lon", "direction": "east", "unit": "degree"}, {"name": "Latitude", "abbreviation": "lat", "direction": "north", "unit": "degree"}]}, "id": {"authority": "EPSG", "code": 4326}}'
# The same object, keys reordered.
wgs84_reordered <- '{"id": {"code": 4326, "authority": "EPSG"}, "name": "WGS 84", "type": "GeographicCRS", "coordinate_system": {"axis": [{"name": "Longitude", "abbreviation": "lon", "direction": "east", "unit": "degree"}, {"name": "Latitude", "abbreviation": "lat", "direction": "north", "unit": "degree"}], "subtype": "ellipsoidal"}, "datum": {"ellipsoid": {"inverse_flattening": 298.257223563, "semi_major_axis": 6378137, "name": "WGS 84"}, "name": "World Geodetic System 1984", "type": "GeodeticReferenceFrame"}, "$schema": "https://proj.org/schemas/v0.7/projjson.schema.json"}'
# Renamed, no $schema, and the axis written 6378137.0: the same coordinates.
wgs84_renamed <- sub('"WGS 84", "datum"', '"World Geodetic System", "datum"',
  sub('"semi_major_axis": 6378137,', '"semi_major_axis": 6378137.0,',
    sub('"\\$schema": "[^"]*", ', "", wgs84)))
# No id, so no authority code.
wgs84_anonymous <- sub(', "id": \\{[^}]*\\}', "", wgs84)
nad83 <- sub('"code": 4326', '"code": 4269', sub("298.257223563", "298.257222101", wgs84))
wkt2 <- 'GEOGCRS["WGS 84", DATUM["World Geodetic System 1984", ELLIPSOID["WGS 84", 6378137, 298.257223563]], CS[ellipsoidal, 2], AXIS["longitude", east], AXIS["latitude", north], UNIT["degree", 0.0174532925199433]]'
wkt2_other <- sub("WGS 84", "WGS84", wkt2, fixed = TRUE)
