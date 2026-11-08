## Test environments

R CMD check --as-cran, through the r-actions workflows (https://github.com/pedrobtz/r-actions) on GitHub Actions:

* macOS (latest), R release
* Windows (latest), R release and R-devel
* Ubuntu (latest), R release and R oldrel-1
* R-hub containers: clang23 (CRAN's compiler major, `-std=gnu23` and CRAN's C flags), ubuntu-clang and ubuntu-gcc16, R-devel
* R-hub `nosuggests` (no suggested package installed) and `nold` (R built with `--disable-long-double`)
* AddressSanitizer and UndefinedBehaviorSanitizer (gcc and clang), valgrind, LTO, rchk, gctorture, and the CRAN special checks

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Notes for the reviewer

* zugeo bundles the C libraries geoarrow-c (Apache-2.0) and the nanoarrow core (Apache-2.0) in `src/vendor/`, with their authors as copyright holders in `Authors@R` and the notices in `inst/COPYRIGHTS`. Its own code is MIT. No system library is needed.
* The tests that use the geoarrow-data example files skip on CRAN: those files carry no licence, so they are not in the package, and are fetched only when `ZUGEO_FETCH_FIXTURES=true`.
* The GeoParquet functions need the suggested package qio; their examples run only when it is installed.

## Method References

There are no published references describing the methods in this package. It implements the GeoArrow (<https://geoarrow.org/>) and GeoParquet (<https://geoparquet.org/>) specifications, and its spatial indexes reproduce the byte formats of the flatbush and kdbush JavaScript libraries.
