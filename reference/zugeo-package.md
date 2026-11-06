# zugeo: 'GeoArrow' Geometry Columns, Exact or an Error

Makes 'GeoArrow' geometry columns first-class R vectors. Points, lines
and polygons stay in 'Apache Arrow' memory with their coordinate
reference system and edge type, move between the native, well-known
binary and well-known text encodings exactly or raise an error, and get
bounding boxes, spatial sorting and packed spatial indexes computed over
the coordinate buffers. The bundled 'geoarrow-c' library
(<https://github.com/geoarrow/geoarrow-c>) needs no system library. The
format is specified at <https://geoarrow.org/>.

## See also

Useful links:

- <https://github.com/pedrobtz/zugeo>

- <https://pedrobtz.github.io/zugeo/>

- Report bugs at <https://github.com/pedrobtz/zugeo/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- Dewey Dunnington (geoarrow-c, bundled in src/vendor/geoarrow)
  \[copyright holder\]

- The Apache Software Foundation (nanoarrow, bundled in
  src/vendor/nanoarrow) \[copyright holder\]

- Ulf Adams (ryu, bundled in src/vendor/geoarrow/ryu) \[copyright
  holder\]
