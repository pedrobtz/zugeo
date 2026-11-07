# Random boxes and brute-force answers for the index tests.
random_boxes <- function(n, seed = 1, size = 2) {
  withr::with_seed(seed, {
    x0 <- runif(n, 0, 100)
    y0 <- runif(n, 0, 100)
    geo_extent(x0, y0, x0 + runif(n, 0, size), y0 + runif(n, 0, size))
  })
}

brute_box <- function(e, q) {
  which(e$xmin <= q$xmax & e$xmax >= q$xmin & e$ymin <= q$ymax & e$ymax >= q$ymin)
}

brute_box_distance <- function(e, x, y) {
  dx <- pmax(pmax(e$xmin - x, x - e$xmax), 0)
  dy <- pmax(pmax(e$ymin - y, y - e$ymax), 0)
  sqrt(dx * dx + dy * dy)
}
