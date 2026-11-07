# Little-endian EWKB of POINT (x y) with an SRID.
ewkb_point <- function(x, y, srid) {
  c(
    as.raw(1),
    writeBin(0x20000001L, raw(), size = 4, endian = "little"),
    writeBin(as.integer(srid), raw(), size = 4, endian = "little"),
    writeBin(c(x, y), raw(), size = 8, endian = "little")
  )
}

# Bit-for-bit equality of two double vectors, NaN payloads included.
same_bits <- function(a, b) {
  length(a) == length(b) &&
    identical(writeBin(as.double(a), raw()), writeBin(as.double(b), raw()))
}

# Doubles that stress text round trips: the shortest-digit edge cases.
hard_doubles <- function(n = 200L) {
  withr::with_seed(20261107, {
    random <- c(
      runif(n, -180, 180),
      runif(n, -1, 1) * 10^runif(n, -30, 30),
      rnorm(n) * 1e-5
    )
  })
  c(
    0, -0, 1, -1, 0.1, 0.2, 0.3, 1 / 3, 2 / 3, 0.01234567890123456,
    1e-20, 1e-300, 4.9e-324, 2.2250738585072014e-308, 1.7976931348623157e308,
    -1.7976931348623157e308, 1e17, 1e17 - 16, 123456789012345678, 1e21, 1e22,
    5e-7, 9007199254740993, .Machine$double.eps, 180, -180, 90, -90,
    random
  )
}
