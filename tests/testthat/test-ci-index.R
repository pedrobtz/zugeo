# Index bytes against flatbush and kdbush in node, and query results
# against geo-index in Python (design section 9, "Indexes"; Stage 6). Run in
# CI by oracles.yaml, which installs flatbush@4.7.0 and kdbush@4.1.0 into
# ZUGEO_NODE_MODULES and geoindex-rs into the Python at ZUGEO_GEOINDEX_PYTHON.

test_that("flatbush and kdbush build the same bytes and answer the same", {
  modules <- skip_without_tool("ZUGEO_NODE_MODULES")
  script <- normalizePath(test_path("..", "..", "tools", "index-oracle.mjs"))
  for (case in list(c(1, 16, 64), c(17, 16, 64), c(300, 4, 8), c(5000, 16, 64), c(70000, 16, 64))) {
    n <- case[[1]]
    e <- random_boxes(n, seed = n)
    dir <- write_inputs(e, case[[2]], case[[3]])
    out <- withr::with_dir(modules, system2("node", c(shQuote(script),
      shQuote(file.path(dir, c("boxes.csv", "rtree.bin", "kd.bin"))), case[[2]], case[[3]]),
      stdout = TRUE))
    res <- zujson::json_parse(paste(out, collapse = ""), simplify = FALSE)
    label <- paste(case, collapse = "/")
    expect_true(res$rtree_bytes_equal, label = label)
    expect_true(res$kdtree_bytes_equal, label = label)
    tree <- geo_rtree(e, node_size = case[[2]])
    queries <- list(c(10, 10, 20, 15), c(50, 50, 52, 60), c(-5, -5, 0, 0), c(0, 0, 100, 100))
    for (i in seq_along(queries)) {
      q <- queries[[i]]
      expect_identical(as.integer(unlist(res$search[[i]])),
        geo_query_box(tree, geo_extent(q[1], q[2], q[3], q[4])), label = paste(label, i))
    }
    kd <- geo_kdtree(geo_points(e$xmin, e$ymin), node_size = case[[3]])
    expect_identical(as.integer(unlist(res$range)), geo_query_box(kd, geo_extent(10, 10, 12, 14)))
    expect_identical(as.integer(unlist(res$within)), geo_query_radius(kd, 50, 50, 3))
    nn <- geo_query_nearest(tree, 50, 50, k = 5)
    want <- brute_box_distance(e, 50, 50)[as.integer(unlist(res$neighbors))]
    expect_equal(nn$distance, want, label = label)
  }
})

test_that("geo-index in Python answers the same box queries", {
  python <- skip_without_tool("ZUGEO_GEOINDEX_PYTHON")
  e <- random_boxes(3000, seed = 12)
  dir <- write_inputs(e, 16, 64)
  code <- paste(
    "import sys, numpy as np, geoindex_rs as g",
    "b = np.loadtxt(sys.argv[1], delimiter=',', skiprows=1)",
    "t = g.RTree.from_interleaved(b, node_size=16)",
    "for q in ([10, 10, 20, 15], [50, 50, 52, 60], [0, 0, 100, 100]):",
    "    print(','.join(str(int(i) + 1) for i in sorted(t.search(*q))))",
    sep = "\n"
  )
  script <- file.path(dir, "q.py")
  writeLines(code, script)
  out <- system2(python, c("-I", shQuote(script), shQuote(file.path(dir, "boxes.csv"))), stdout = TRUE)
  tree <- geo_rtree(e)
  queries <- list(c(10, 10, 20, 15), c(50, 50, 52, 60), c(0, 0, 100, 100))
  for (i in seq_along(queries)) {
    q <- queries[[i]]
    expect_identical(as.integer(strsplit(out[[i]], ",")[[1]]),
      geo_query_box(tree, geo_extent(q[1], q[2], q[3], q[4])), label = i)
  }
})
