# Changelog

## zugeo 0.0.0.9000

- [`zugeo_info()`](https://pedrobtz.github.io/zugeo/reference/zugeo_info.md)
  reports the bundled geoarrow-c and nanoarrow versions and the GeoArrow
  specification version implemented.

- [`geo_type_of()`](https://pedrobtz.github.io/zugeo/reference/geo_type_of.md)
  describes a GeoArrow field from its Arrow schema: every GeoArrow 0.2
  extension name, both coordinate layouts, `list` and `large_list`
  offsets and the view storage types, with layout errors for what the
  specification forbids.

- [`geo_crs()`](https://pedrobtz.github.io/zugeo/reference/geo_crs.md)
  carries a coordinate reference system exactly as given, typed as
  GeoArrow asks, and
  [`geo_crs_equal()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_equal.md)
  compares two at three levels without PROJ.

- `geo_vctr` holds geometries in the Arrow arrays they were read in, as
  positions, so subsetting, [`rev()`](https://rdrr.io/r/base/rev.html)
  and [`c()`](https://rdrr.io/r/base/c.html) copy no buffer. With zugeo
  loaded, zuarrow reads every GeoArrow column as one and writes it back
  with its extension metadata unchanged;
  [`format()`](https://rdrr.io/r/base/format.html) gives WKT.

- [`geo_vctr()`](https://pedrobtz.github.io/zugeo/reference/geo_vctr.md)
  reads WKB, EWKB (its SRID becomes the CRS), hex WKB and WKT, checking
  every element, and
  [`geo_as_wkb()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md),
  [`geo_as_wkt()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md)
  and
  [`geo_as_native()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md)
  convert between encodings. Coordinates round-trip through WKT bit for
  bit: numbers print as the shortest text that reads back the same,
  through zufast.

- [`geo_coords()`](https://pedrobtz.github.io/zugeo/reference/geo_coords.md),
  [`geo_from_coords()`](https://pedrobtz.github.io/zugeo/reference/geo_coords.md)
  and
  [`geo_points()`](https://pedrobtz.github.io/zugeo/reference/geo_coords.md)
  move coordinates to and from columns;
  [`geo_crs_text()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_text.md)
  gives the CRS as one string for sf and PROJ.

- Converting to WKB or WKT is an error when it would drop a non-planar
  edge type from geometries with edges; `lossy = "warn"` or `"allow"`
  converts anyway. A null inside a geometry is a layout error when a
  column is read.
  [`geo_coords()`](https://pedrobtz.github.io/zugeo/reference/geo_coords.md)
  carries the CRS and edges to
  [`geo_from_coords()`](https://pedrobtz.github.io/zugeo/reference/geo_coords.md).

- [`geo_box()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md),
  [`geo_box_all()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md),
  [`geo_types()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md),
  [`geo_dims()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md)
  and
  [`geo_n_coords()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md)
  compute over the coordinate buffers; boxes are `geo_extent` vectors
  with
  [`geo_extent_union()`](https://pedrobtz.github.io/zugeo/reference/geo_extent.md),
  [`geo_extent_intersection()`](https://pedrobtz.github.io/zugeo/reference/geo_extent.md)
  and
  [`geo_extent_intersects()`](https://pedrobtz.github.io/zugeo/reference/geo_extent.md).

- [`geo_hilbert()`](https://pedrobtz.github.io/zugeo/reference/geo_hilbert.md)
  and
  [`geo_sort()`](https://pedrobtz.github.io/zugeo/reference/geo_hilbert.md)
  give flatbush’s Hilbert keys exactly, the same as DuckDB’s
  `ST_Hilbert`.
  [`geo_validate()`](https://pedrobtz.github.io/zugeo/reference/geo_validate.md)
  reports unclosed or short rings, non-finite coordinates, mixed
  dimensions and winding.

- [`geo_rtree()`](https://pedrobtz.github.io/zugeo/reference/geo_rtree.md)
  and
  [`geo_kdtree()`](https://pedrobtz.github.io/zugeo/reference/geo_rtree.md)
  build packed indexes in flatbush’s and kdbush’s formats, byte for
  byte, so
  [`geo_index_raw()`](https://pedrobtz.github.io/zugeo/reference/geo_rtree.md)
  bytes load in flatbush, kdbush and geo-index.
  [`geo_query_box()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md),
  [`geo_query_radius()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md),
  [`geo_query_nearest()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md)
  and
  [`geo_join_box()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md)
  query them;
  [`geo_join_box()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md)
  descends two indexes together.
  [`geo_index_from_raw()`](https://pedrobtz.github.io/zugeo/reference/geo_rtree.md)
  checks bytes before use.
