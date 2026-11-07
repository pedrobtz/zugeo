# Symbol tables of the loaded zugeo shared object, read with the binutils
# the toolchain ships: nm on Linux and macOS, objdump on Windows. Names are
# returned without the leading underscore macOS adds and without a glibc
# version suffix.
# Coverage instrumentation adds gcov's own exports and imports, so the
# symbol tests describe the shipped object only when it is not instrumented.
abi_skip_instrumented <- function() {
  testthat::skip_if(
    identical(Sys.getenv("R_COVR"), "true"),
    "the shared object is instrumented for coverage"
  )
}

abi_dll_path <- function() {
  getLoadedDLLs()[["zugeo"]][["path"]]
}

# A symbol table that can't be read ends the test. On CI, where the guards
# must run, that is a failure; elsewhere, such as a machine without
# binutils, it is a skip. The tests skip_on_cran() themselves.
abi_unavailable <- function(reason) {
  if (nzchar(Sys.getenv("CI"))) {
    testthat::fail(paste0(reason, ", so the ABI guard can't run on CI"))
  }
  testthat::skip(reason)
}

abi_tool <- function(name) {
  path <- Sys.which(name)
  if (!nzchar(path)) {
    abi_unavailable(paste(name, "is not on the PATH"))
  }
  path
}

abi_run <- function(tool, args) {
  out <- suppressWarnings(system2(tool, args, stdout = TRUE, stderr = FALSE))
  if (!is.null(attr(out, "status"))) {
    abi_unavailable(paste(basename(tool), "failed"))
  }
  # objdump on Windows ends its lines with \r, which the patterns below
  # would otherwise read as part of a symbol name.
  sub("\r$", "", out)
}

abi_clean <- function(x) {
  x <- sub("@.*$", "", x)
  if (Sys.info()[["sysname"]] == "Darwin") {
    x <- sub("^_", "", x)
  }
  x
}

abi_objdump <- function(path = abi_dll_path()) {
  abi_run(abi_tool("objdump"), c("-p", shQuote(path)))
}

abi_exports <- function() {
  abi_exports_of(abi_dll_path())
}

# The export table of any shared object, such as another loaded package's.
abi_exports_of <- function(path) {
  if (.Platform$OS.type == "windows") {
    out <- abi_objdump(path)
    start <- grep("[Ordinal/Name Pointer] Table", out, fixed = TRUE)
    if (length(start) != 1L) {
      abi_unavailable("objdump printed no export table")
    }
    rows <- out[-seq_len(start)]
    rows <- rows[grepl("^\\s*\\[\\s*[0-9]+\\]", rows)]
    return(sub("^.*\\s", "", trimws(rows)))
  }
  nm <- abi_tool("nm")
  args <- if (Sys.info()[["sysname"]] == "Darwin") {
    c("-gU", shQuote(path))
  } else {
    c("-D", "--defined-only", shQuote(path))
  }
  out <- abi_run(nm, args)
  abi_clean(sub("^.*\\s", "", trimws(out[nzchar(out)])))
}

abi_imports <- function() {
  if (.Platform$OS.type == "windows") {
    return(abi_windows_imports(abi_objdump()))
  }
  out <- abi_run(abi_tool("nm"), c("-u", shQuote(abi_dll_path())))
  abi_clean(sub("^.*\\s", "", trimws(out[nzchar(out)])))
}

# The symbols R CMD check's compiled-code check reports, across platforms,
# with leading underscores removed so one list covers macOS too.
abi_forbidden <- c(
  "abort",
  "exit",
  "_exit",
  "_Exit",
  "printf",
  "puts",
  "putchar",
  "sprintf",
  "vprintf",
  "vsprintf",
  "sprintf_chk",
  "vsprintf_chk",
  "rand",
  "random",
  "rand_r",
  "srand",
  "srandom",
  "srand48",
  "stderr",
  "stdout",
  "stderrp",
  "stdoutp",
  "iob_func",
  "acrt_iob_func",
  "assert",
  "assert_fail",
  "assert_rtn"
)

# The imported names in `objdump -p` output: after each "DLL Name:" line, a
# header row and then one row per symbol, whose last token is the name,
# until a blank line. Parsed by that structure rather than by columns,
# which differ across binutils versions.
abi_windows_imports <- function(out) {
  imports <- character()
  starts <- grep("^\\s*DLL Name:", out)
  for (start in starts) {
    i <- start + 1L
    while (i <= length(out) && nzchar(trimws(out[[i]]))) {
      row <- trimws(out[[i]])
      if (!grepl("Member-Name|^vma:", row)) {
        imports <- c(imports, sub("^.*\\s", "", row))
      }
      i <- i + 1L
    }
  }
  if (length(imports) == 0L) {
    section <- grep("Import Tables", out)
    from <- if (length(section)) section[[1L]] else 1L
    testthat::fail(paste(
      c("objdump -p printed no import rows; its import section:",
        out[seq(from, min(length(out), from + 40L))]),
      collapse = "\n"
    ))
  }
  imports
}

# The names in the package's own object files, from the symbols.rds that R
# CMD check writes beside the shared object, or NULL outside a check. R's
# compiled-code check reports a symbol only when an object file references
# it, which leaves out the C runtime the toolchain links in: MinGW's
# startup code imports exit, abort and __acrt_iob_func on Windows.
abi_object_symbols <- function() {
  path <- file.path(dirname(abi_dll_path()), "symbols.rds")
  if (!file.exists(path)) {
    return(NULL)
  }
  tables <- readRDS(path)
  sub("^_+", "", unique(unlist(lapply(tables, function(t) t[, "name"]))))
}
