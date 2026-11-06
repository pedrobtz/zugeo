zgo_extension_names <- c(
  "geoarrow.point", "geoarrow.linestring", "geoarrow.polygon",
  "geoarrow.multipoint", "geoarrow.multilinestring", "geoarrow.multipolygon",
  "geoarrow.geometry", "geoarrow.geometrycollection", "geoarrow.box",
  "geoarrow.wkb", "geoarrow.wkt"
)

# zuarrow's `to`: one batch's array of a GeoArrow column (design section
# 6.5). `lossy` reaches it for the Stage 4 policy.
zgo_arrow_to_r <- function(array, schema, lossy) {
  zgo_from_array(array, schema, call = sys.call(-1))
}

# zuarrow's `from`: the whole column.
zgo_arrow_from_r <- function(x) {
  zgo_to_array(x)
}

.onLoad <- function(libname, pkgname) {
  for (name in zgo_extension_names) {
    zuarrow::arrow_register(name, to = zgo_arrow_to_r, package = pkgname)
  }
  zuarrow::arrow_register(
    "geo_vctr",
    from = zgo_arrow_from_r,
    class = "geo_vctr",
    package = pkgname
  )
}
