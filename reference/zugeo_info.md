# Versions zugeo is built from

Reports the package version, the bundled 'geoarrow-c' library (its
version and the commit it is vendored from), the bundled 'nanoarrow'
core, and the version of the GeoArrow specification implemented.

## Usage

``` r
zugeo_info()
```

## Value

A named list of character strings: `zugeo`, `geoarrow_c`,
`geoarrow_c_commit`, `nanoarrow` and `geoarrow`.

## Examples

``` r
zugeo_info()
#> $zugeo
#> [1] "0.1.0"
#> 
#> $geoarrow_c
#> [1] "0.2.0-SNAPSHOT"
#> 
#> $geoarrow_c_commit
#> [1] "b3db89fec68043ade505fffb62a668043812884a"
#> 
#> $nanoarrow
#> [1] "0.9.0"
#> 
#> $geoarrow
#> [1] "0.2"
#> 
```
