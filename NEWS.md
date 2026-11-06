# zugeo 0.0.0.9000

* `zugeo_info()` reports the bundled geoarrow-c and nanoarrow versions and
  the GeoArrow specification version implemented.

* `geo_type_of()` describes a GeoArrow field from its Arrow schema: every
  GeoArrow 0.2 extension name, both coordinate layouts, `list` and
  `large_list` offsets and the view storage types, with layout errors for
  what the specification forbids.
* `geo_crs()` carries a coordinate reference system exactly as given, typed
  as GeoArrow asks, and `geo_crs_equal()` compares two at three levels
  without PROJ.

* `geo_vctr` holds geometries in the Arrow arrays they were read in, as
  positions, so subsetting, `rev()` and `c()` copy no buffer. With zugeo
  loaded, zuarrow reads every GeoArrow column as one and writes it back
  with its extension metadata unchanged; `format()` gives WKT.
