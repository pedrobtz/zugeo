# a box column is its own boxes, and refuses the geometry kernels

    Code
      geo_types(b)
    Condition
      Error in `geo_types()`:
      ! `x` is a geoarrow.box column: it holds boxes, not geometries. geo_box() gives them as a geo_extent.

