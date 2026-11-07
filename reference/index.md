# Package index

## Geometry vectors

GeoArrow columns as R vectors, read from WKB, WKT or any Arrow producer,
and converted between encodings exactly or with an error.

- [`geo_vctr()`](https://pedrobtz.github.io/zugeo/reference/geo_vctr.md)
  [`is_geo_vctr()`](https://pedrobtz.github.io/zugeo/reference/geo_vctr.md)
  : Make geometry vectors from WKB, WKT or Arrow
- [`geo_as_wkb()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md)
  [`geo_as_wkt()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md)
  [`geo_as_native()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md)
  : Convert geometries between encodings
- [`geo_coords()`](https://pedrobtz.github.io/zugeo/reference/geo_coords.md)
  [`geo_from_coords()`](https://pedrobtz.github.io/zugeo/reference/geo_coords.md)
  [`geo_points()`](https://pedrobtz.github.io/zugeo/reference/geo_coords.md)
  : Coordinates as columns
- [`geo_type_of()`](https://pedrobtz.github.io/zugeo/reference/geo_type_of.md)
  : Describe a GeoArrow field

## Coordinate reference systems

Carried exactly as given, and compared without PROJ.

- [`geo_crs()`](https://pedrobtz.github.io/zugeo/reference/geo_crs.md) :
  Coordinate reference systems, carried exactly
- [`geo_crs_equal()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_equal.md)
  : Compare two coordinate reference systems without PROJ
- [`geo_crs_text()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_text.md)
  : The CRS as one string for other packages

## Kernels

Boxes, types, Hilbert keys, sorting and validation over the buffers.

- [`geo_box()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md)
  [`geo_box_all()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md)
  [`geo_types()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md)
  [`geo_dims()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md)
  [`geo_n_coords()`](https://pedrobtz.github.io/zugeo/reference/geo_box.md)
  : Bounds, types and counts over the buffers
- [`geo_extent()`](https://pedrobtz.github.io/zugeo/reference/geo_extent.md)
  [`geo_extent_union()`](https://pedrobtz.github.io/zugeo/reference/geo_extent.md)
  [`geo_extent_intersection()`](https://pedrobtz.github.io/zugeo/reference/geo_extent.md)
  [`geo_extent_intersects()`](https://pedrobtz.github.io/zugeo/reference/geo_extent.md)
  : Extents: boxes as a vector
- [`geo_hilbert()`](https://pedrobtz.github.io/zugeo/reference/geo_hilbert.md)
  [`geo_sort()`](https://pedrobtz.github.io/zugeo/reference/geo_hilbert.md)
  : Hilbert keys and spatial sorting
- [`geo_validate()`](https://pedrobtz.github.io/zugeo/reference/geo_validate.md)
  : Report what is wrong with geometries, without repairing it

## Spatial indexes

Packed R-trees and k-d trees in flatbush’s and kdbush’s formats.

- [`geo_rtree()`](https://pedrobtz.github.io/zugeo/reference/geo_rtree.md)
  [`geo_kdtree()`](https://pedrobtz.github.io/zugeo/reference/geo_rtree.md)
  [`geo_index_raw()`](https://pedrobtz.github.io/zugeo/reference/geo_rtree.md)
  [`geo_index_from_raw()`](https://pedrobtz.github.io/zugeo/reference/geo_rtree.md)
  : Packed spatial indexes
- [`geo_query_box()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md)
  [`geo_query_radius()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md)
  [`geo_query_nearest()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md)
  [`geo_join_box()`](https://pedrobtz.github.io/zugeo/reference/geo_query_box.md)
  : Query packed indexes

## GeoParquet

Reading, writing, inspecting and validating, with the qio package.

- [`geo_read_parquet()`](https://pedrobtz.github.io/zugeo/reference/geo_read_parquet.md)
  [`geo_write_parquet()`](https://pedrobtz.github.io/zugeo/reference/geo_read_parquet.md)
  : Read and write GeoParquet
- [`geo_parquet_info()`](https://pedrobtz.github.io/zugeo/reference/geo_parquet_info.md)
  : GeoParquet metadata without reading rows
- [`geo_validate_parquet()`](https://pedrobtz.github.io/zugeo/reference/geo_validate_parquet.md)
  : Report what is wrong with a GeoParquet file

## About the package

- [`zugeo_info()`](https://pedrobtz.github.io/zugeo/reference/zugeo_info.md)
  : Versions zugeo is built from
- [`zugeo`](https://pedrobtz.github.io/zugeo/reference/zugeo-package.md)
  [`zugeo-package`](https://pedrobtz.github.io/zugeo/reference/zugeo-package.md)
  : zugeo: 'GeoArrow' Geometry Columns, Exact or an Error
