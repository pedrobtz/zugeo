# Geometry columns from DuckDB to sf

A geometry column often starts in a database, is filtered and sorted
somewhere in the middle, and ends in sf for a map or a spatial join.
Each hand-off is a chance to lose something: digits when the column
travels as text, the coordinate reference system when a reader does not
know where to look for it, the meaning of an edge when a line on the
sphere is read as a straight one.

This article follows one column from DuckDB to sf and back, with zugeo
holding it in between. None of DuckDB, sf or qio is needed by zugeo; the
article uses all three.

``` r

library(zugeo)
con <- DBI::dbConnect(duckdb::duckdb())
invisible(DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;"))
```

## From DuckDB, as GeoParquet

DuckDB writes a query result as GeoParquet, with the CRS in the file.
Here are ten thousand random points over Iberia, in WGS 84 longitude and
latitude.

``` r

path <- tempfile(fileext = ".parquet")
invisible(DBI::dbExecute(con, "SELECT setseed(0.42)"))
invisible(DBI::dbExecute(con, sprintf("
  COPY (
    SELECT i AS id,
           ST_SetCRS(ST_Point(-9.5 + random() * 12.5, 36 + random() * 7.8),
                     'OGC:CRS84') AS geometry
    FROM range(10000) t(i)
  ) TO '%s' (FORMAT parquet, GEOPARQUET_VERSION 'BOTH')", path)))
```

[`geo_parquet_info()`](https://pedrobtz.github.io/zugeo/reference/geo_parquet_info.md)
reads the footer and nothing else: the row count, the encoding, the CRS
DuckDB stored, and the box from the column’s statistics.

``` r

geo_parquet_info(path)
#> <zugeo_parquet_info: 10,000 rows in 1 row groups; GeoParquet 1.0.0>
#> * geometry: WKB GEOMETRY; Point; crs projjson: WGS 84 (CRS84); edges planar; bbox [-9.49522715809373 36.0000097816499, 2.99996306555653 43.7997633161704]
```

[`geo_read_parquet()`](https://pedrobtz.github.io/zugeo/reference/geo_read_parquet.md)
gives a data frame whose geometry column is a `geo_vctr`, its CRS taken
from the file.

``` r

df <- geo_read_parquet(path)
head(df, 3)
#>   id                                      geometry
#> 1  0 POINT (-0.1599482076109382 39.44579523739312)
#> 2  1 POINT (-1.0796949709503902 38.57168598702719)
#> 3  2 POINT (-1.9511585203605986 39.79967235830755)
geo_crs(df$geometry)
#> <zugeo_crs projjson: WGS 84 (CRS84)>
```

## In zugeo

The column stays in Arrow memory. Its boxes, Hilbert keys and index are
computed over the coordinates. Sorting by Hilbert key puts nearby points
next to each other, which is what makes a file’s row groups prunable.

``` r

df <- df[geo_sort(df$geometry), ]
geo_box_all(df$geometry)
#> <geo_extent[1]; crs projjson: WGS 84 (CRS84); edges planar>
#> [1] [-9.49522715809373 36.0000097816499, 2.99996306555653 43.7997633161704]
```

A packed R-tree answers “which points fall in this box”, here a box
around Lisbon.

``` r

tree <- geo_rtree(df$geometry)
lisbon <- geo_extent(-9.5, 38.5, -8.9, 39, crs = geo_crs(df$geometry))
near <- geo_query_box(tree, lisbon)
length(near)
#> [1] 28
```

## To sf

WKB is the bridge:
[`geo_as_wkb()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md)
gives a list of raw vectors that sf reads directly, and
[`geo_crs_text()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_text.md)
gives the CRS in a form PROJ reads.

``` r

pts <- sf::st_sf(
  id = df$id[near],
  geometry = sf::st_as_sfc(
    unclass(geo_as_wkb(df$geometry[near])),
    crs = geo_crs_text(df$geometry)
  )
)
pts[1:3, ]
#> Simple feature collection with 3 features and 1 field
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: -9.472545 ymin: 38.5073 xmax: -9.415429 ymax: 38.55168
#> Geodetic CRS:  WGS 84 (CRS84)
#>     id                   geometry
#> 1 5375 POINT (-9.440974 38.54394)
#> 2  810  POINT (-9.415429 38.5073)
#> 3 8390 POINT (-9.472545 38.55168)
sf::st_crs(pts) == sf::st_crs("OGC:CRS84")
#> [1] TRUE
```

Nothing was rounded on the way. The coordinates sf holds are the doubles
DuckDB wrote, bit for bit.

``` r

back <- geo_vctr(sf::st_as_binary(sf::st_geometry(pts)))
identical(geo_coords(back)[c("x", "y")], geo_coords(df$geometry[near])[c("x", "y")])
#> [1] TRUE
```

## And back to GeoParquet

A geometry column from sf comes back the same way, with its CRS given
explicitly, and goes out as GeoParquet 2.0. DuckDB reads it and finds
the same extent zugeo does.

``` r

out <- tempfile(fileext = ".parquet")
again <- data.frame(id = pts$id)
again$geometry <- geo_vctr(sf::st_as_binary(sf::st_geometry(pts)),
  crs = sf::st_crs(pts)$input
)
geo_write_parquet(again, out)
DBI::dbGetQuery(con, sprintf(paste(
  "SELECT count(*) AS n, min(ST_X(geometry)) AS xmin, max(ST_X(geometry)) AS xmax",
  "FROM '%s'"
), out))
#>    n      xmin      xmax
#> 1 28 -9.489615 -8.936077
geo_box_all(again$geometry)
#> <geo_extent[1]; crs projjson: WGS 84 (CRS84); edges planar>
#> [1] [-9.48961521673695 38.5072950083719, -8.93607727962498 38.9574014626128]
```

## Where the guarantees stop

zugeo carries a CRS but does not interpret it:
[`geo_crs_equal()`](https://pedrobtz.github.io/zugeo/reference/geo_crs_equal.md)
compares two without PROJ, and anything that needs a transformation is
sf’s or PROJ’s job. Lines with spherical edges are carried and written
as GeoParquet `GEOGRAPHY`, but a planar box or a planar Hilbert key of
them is refused unless asked for with `lossy`, because it can be wrong.
And WKB has no place for an edge type, so
[`geo_as_wkb()`](https://pedrobtz.github.io/zugeo/reference/geo_as_wkb.md)
on such lines is an error by default: sf would read them as planar.
