# zugeo 0.1.0

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

* `geo_vctr()` reads WKB, EWKB (its SRID becomes the CRS), hex WKB and WKT,
  checking every element, and `geo_as_wkb()`, `geo_as_wkt()` and
  `geo_as_native()` convert between encodings. Coordinates round-trip
  through WKT bit for bit: numbers print as the shortest text that reads
  back the same, through zufast.
* `geo_coords()`, `geo_from_coords()` and `geo_points()` move coordinates
  to and from columns; `geo_crs_text()` gives the CRS as one string for
  sf and PROJ.

* Converting to WKB or WKT is an error when it would drop a non-planar
  edge type from geometries with edges; `lossy = "warn"` or `"allow"`
  converts anyway. A null inside a geometry is a layout error when a column
  is read. `geo_coords()` carries the CRS and edges to `geo_from_coords()`.

* `geo_box()`, `geo_box_all()`, `geo_types()`, `geo_dims()` and
  `geo_n_coords()` compute over the coordinate buffers; boxes are
  `geo_extent` vectors with `geo_extent_union()`, `geo_extent_intersection()`
  and `geo_extent_intersects()`.
* `geo_hilbert()` and `geo_sort()` give flatbush's Hilbert keys exactly,
  the same as DuckDB's `ST_Hilbert`. `geo_validate()` reports unclosed or
  short rings, non-finite coordinates, mixed dimensions and winding.

* `geo_rtree()` and `geo_kdtree()` build packed indexes in flatbush's and
  kdbush's formats, byte for byte, so `geo_index_raw()` bytes load in
  flatbush, kdbush and geo-index. `geo_query_box()`, `geo_query_radius()`,
  `geo_query_nearest()` and `geo_join_box()` query them; `geo_join_box()`
  descends two indexes together. `geo_index_from_raw()` checks bytes before
  use.

* With qio 0.1.2, `geo_read_parquet()` and `geo_write_parquet()` read and
  write GeoParquet 2.0 and 1.1: WKB in the native `GEOMETRY` and
  `GEOGRAPHY` types with the `geo` key beside them, CRS and edges checked
  to agree, rows in Hilbert order, and `bbox =` skipping row groups by
  their statistics. `geo_parquet_info()` reads the footer alone, and
  `geo_validate_parquet()` reports what `gpq validate` checks, what
  GeoParquet 2.0 adds and the distribution guide's advice.

* `geo_sort()` and `geo_hilbert()` compute each box once, not twice.
* A README, the article "Geometry columns from DuckDB to sf", and a
  reference index by task.
