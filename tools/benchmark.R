#!/usr/bin/env Rscript
# The performance targets of design section 10, measured on 10^6 polygons of
# 10 vertices, with sf and wk (through geoarrow's WKB) beside them where they
# do the same job. CI-only, like the oracles: benchmark.yaml runs it on
# ubuntu-latest and the numbers go into design.md section 10.
#
#   Rscript tools/benchmark.R [--n 1000000] [--reps 5] [--out results.json]

args <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default) {
  i <- match(paste0("--", name), args)
  if (is.na(i)) default else args[[i + 1L]]
}
n <- as.integer(opt("n", 1e6))
reps <- as.integer(opt("reps", 5))
out <- opt("out", NA_character_)

suppressPackageStartupMessages(library(zugeo))
have <- function(pkg) requireNamespace(pkg, quietly = TRUE)

# Median wall time in milliseconds of `reps` runs of `expr`, after one warm-up.
time_ms <- function(expr, reps_ = reps) {
  e <- substitute(expr)
  env <- parent.frame()
  eval(e, env)
  t <- vapply(seq_len(reps_), function(i) {
    gc(FALSE)
    s <- proc.time()[["elapsed"]]
    eval(e, env)
    (proc.time()[["elapsed"]] - s) * 1000
  }, numeric(1))
  stats::median(t)
}

# 10^6 decagons (nine vertices and the closing one) around random centres.
set.seed(20261107)
k <- 10L
cx <- stats::runif(n, -180, 180)
cy <- stats::runif(n, -85, 85)
angle <- c(seq(0, 2 * pi, length.out = k)[-k], 0)
r <- 0.01
coords <- data.frame(
  x = rep(cx, each = k) + r * cos(angle),
  y = rep(cy, each = k) + r * sin(angle),
  feature = rep(seq_len(n), each = k)
)
x <- geo_from_coords(coords, "polygon", n = n, crs = "OGC:CRS84")
rm(coords)
array <- getFromNamespace("zgo_to_array", "zugeo")(x)

results <- list()
add <- function(op, ms, target, comparison = NA_character_) {
  results[[length(results) + 1L]] <<- list(
    operation = op, ms = round(ms, 2), target = target, comparison = comparison
  )
}

add("arrow_to_r() of a native column to geo_vctr",
  time_ms(zuarrow::arrow_to_r(array)), "under 1 ms; no copy")

box_ms <- time_ms(geo_box(x))
cmp <- NA_character_
if (have("sf")) {
  m <- 1e4L
  sfc <- sf::st_as_sfc(unclass(geo_as_wkb(x[seq_len(m)])))
  sf_ms <- time_ms(for (g in sfc) sf::st_bbox(g), max(1L, reps %/% 2L)) * (n / m)
  cmp <- sprintf("sf::st_bbox() per feature: %.0f ms for %s (from 10^4), %.0fx",
    sf_ms, format(n, big.mark = ","), sf_ms / box_ms)
}
add("geo_box()", box_ms, "at least 10x faster than sf::st_bbox() per feature", cmp)

add("geo_sort()", time_ms(geo_sort(x)), "under 200 ms")
tree <- geo_rtree(x)
add("geo_rtree()", time_ms(geo_rtree(x)), "under 300 ms")

q <- 1e4L
qx <- stats::runif(q, -180, 180)
qy <- stats::runif(q, -85, 85)
queries <- geo_extent(qx, qy, qx + 0.5, qy + 0.5, crs = "OGC:CRS84")
add("10^4 box queries", time_ms(geo_query_box(tree, queries)), "under 50 ms")

wkb_ms <- time_ms(geo_as_wkb(x))
cmp <- NA_character_
if (have("geoarrow") && have("wk")) {
  wkb <- geo_as_wkb(x)
  attributes(wkb) <- NULL
  w <- wk::new_wk_wkb(wkb)
  env_ms <- time_ms(wk::wk_envelope(w))
  cmp <- sprintf("wk::wk_envelope() over the same WKB: %.0f ms (geo_box(): %.0f ms)",
    env_ms, box_ms)
}
add("geo_as_wkb() of a native column", wkb_ms, "under 100 ms", cmp)

cat(sprintf("zugeo %s, R %s, %s; n = %s polygons of %d vertices, median of %d\n\n",
  utils::packageVersion("zugeo"), getRversion(), R.version$platform,
  format(n, big.mark = ","), k, reps))
cat("| Operation | Target | Measured | Comparison |\n| --- | --- | --- | --- |\n")
for (r_ in results) {
  cat(sprintf("| %s | %s | %.1f ms | %s |\n", r_$operation, r_$target, r_$ms,
    if (is.na(r_$comparison)) "" else r_$comparison))
}
if (!is.na(out)) {
  writeLines(as.character(zujson::json_write(results)), out)
}
