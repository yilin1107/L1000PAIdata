# All content in these tests is synthetic. No real signatures or network I/O.
original_integrity_bindings <- mget(
  c("l1000pai_data_sources", ".download_file", ".rename_cache_file",
    ".fetch_download", ".download_sleep"),
  envir = asNamespace("L1000PAIdata"))

synthetic_source_fixture <- function() {
  dir <- tempfile("synthetic-cache-")
  dir.create(dir)
  fixture <- file.path(dir, "fixture.txt")
  writeLines(c("SYNTHETIC up\t\tG1\tG2", "SYNTHETIC dn\t\tG3"), fixture)
  src <- l1000pai_data_sources()
  src$content_sha256 <- l1000pai_content_sha256(fixture)$sha256
  src$n_terms <- "2"
  list(dir = dir, fixture = fixture, sources = src)
}

with_synthetic_source <- function(code) {
  f <- synthetic_source_fixture()
  ns <- asNamespace("L1000PAIdata")
  original <- get("l1000pai_data_sources", ns)
  was_locked <- bindingIsLocked("l1000pai_data_sources", ns)
  set_source <- function(value) {
    if (bindingIsLocked("l1000pai_data_sources", ns)) unlockBinding("l1000pai_data_sources", ns)
    assign("l1000pai_data_sources", value, envir = ns)
    if (was_locked) lockBinding("l1000pai_data_sources", ns)
  }
  # Explicit lexical scope avoids exported-binding restoration interactions in
  # testthat::test_dir(load_package = "installed") followed by another package.
  on.exit({
    set_source(original)
    resolved <- normalizePath(f$dir, winslash = "/", mustWork = TRUE)
    stopifnot(startsWith(resolved, paste0(normalizePath(tempdir(), winslash = "/"),
                                        "/synthetic-cache-")))
    unlink(f$dir, recursive = TRUE)
  }, add = TRUE)
  set_source(function() f$sources)
  eval(substitute(code), envir = environment())
}

test_that("registered content is re-verified on every provider access", with_synthetic_source({
  path <- register_l1000pai_data_file("chem", f$fixture, f$dir)
  expect_identical(get_l1000pai_data_path("chem", f$dir), path)
  expect_identical(unname(list_l1000pai_data_files(f$dir)), path)
  expect_true(verify_l1000pai_data_files(cache_dir = f$dir)$ok[2])
  # Same byte length and restored timestamp defeat metadata-only memoization.
  stamp <- file.info(path)$mtime
  writeLines(c("SYNTHETIC up\t\tG1\tG9", "SYNTHETIC dn\t\tG3"), path)
  Sys.setFileTime(path, stamp)
  expect_error(get_l1000pai_data_path("chem", f$dir), "failed content verification")
  expect_error(list_l1000pai_data_files(f$dir), "overwrite = TRUE")
  expect_error(verify_l1000pai_data_files(cache_dir = f$dir), "overwrite = TRUE")
  expect_identical(unname(list_l1000pai_data_files(f$dir, verify_hash = FALSE)), path)
  report <- verify_l1000pai_data_files(stop_on_error = FALSE, cache_dir = f$dir)
  expect_false(report$ok[report$library_id == "chem"])
  expect_false(report$matches_reference[report$library_id == "chem"])
  register_l1000pai_data_file("chem", f$fixture, f$dir)
  expect_identical(get_l1000pai_data_path("chem", f$dir), path)
}))

test_that("single-library access does not hash unrelated cached libraries", with_synthetic_source({
  chem <- register_l1000pai_data_file("chem", f$fixture, f$dir)
  crispr <- register_l1000pai_data_file("crispr", f$fixture, f$dir)
  writeLines("tampered", crispr)
  expect_identical(get_l1000pai_data_path("chem", f$dir), chem)
  expect_error(get_l1000pai_data_path("crispr", f$dir), "failed content verification")
  oe <- register_l1000pai_data_file("oe", f$fixture, f$dir)
  writeLines("tampered", oe)
  expect_error(get_l1000pai_data_path("oe", f$dir), "register_l1000pai_data_file")
  expect_error(list_l1000pai_data_files(f$dir, verify_hash = NA), "TRUE or FALSE")
}))

test_that("failed and interrupted downloads never replace the raw cache", with_synthetic_source({
  raw <- file.path(f$dir, "cached-raw.txt")
  writeLines("previous complete content", raw)
  for (mode in c("status", "error", "empty", "missing", "null")) {
    testthat::local_mocked_bindings(.download_file = function(url, destfile) {
      if (mode != "missing") writeLines(if (mode == "empty") character() else "partial", destfile)
      if (mode == "error") stop("interrupted synthetic transfer")
      if (mode == "status") return(1L)
      if (mode == "null") return(NULL)
      0L
    }, .package = "L1000PAIdata")
    expect_error(L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", raw),
                 "Download failed")
    expect_identical(readLines(raw), "previous complete content")
    expect_length(list.files(f$dir, pattern = "[.]part$", all.files = TRUE), 0L)
  }
}))

test_that("a failed first download leaves no poison raw file and retry works", with_synthetic_source({
  count <- 0L
  testthat::local_mocked_bindings(.download_file = function(url, destfile) {
    count <<- count + 1L
    if (count == 1L) {
      writeLines("partial", destfile)
      return(1L)
    }
    writeLines(c("SYNTHETIC Up\t\tG1\tG2", "SYNTHETIC Down\t\tG3"), destfile)
    0L
  }, .package = "L1000PAIdata")
  expect_error(download_l1000pai_data("chem", f$dir, quiet = TRUE), "Download failed")
  expect_length(list.files(file.path(f$dir, "raw"), all.files = FALSE), 0L)
  expect_length(list_l1000pai_data_files(f$dir), 0L)
  paths <- download_l1000pai_data("chem", f$dir, quiet = TRUE)
  expect_identical(count, 2L)
  expect_identical(names(paths), "chem")
  expect_identical(get_l1000pai_data_path("chem", f$dir), unname(paths))
  expect_identical(read.csv(file.path(f$dir, "libraries", "download_record.csv"))$library_id,
                   "chem")
}))

test_that("fingerprint mismatch remains actionable and overwrite refreshes raw input", with_synthetic_source({
  count <- 0L
  testthat::local_mocked_bindings(.download_file = function(url, destfile) {
    count <<- count + 1L
    if (count == 1L) writeLines("wrong upstream content", destfile) else {
      writeLines(c("SYNTHETIC Up\t\tG1\tG2", "SYNTHETIC Down\t\tG3"), destfile)
    }
    0L
  }, .package = "L1000PAIdata")
  expect_error(download_l1000pai_data("chem", f$dir, quiet = TRUE), "overwrite = TRUE")
  expect_length(list_l1000pai_data_files(f$dir), 0L)
  expect_length(list.files(file.path(f$dir, "libraries"), all.files = TRUE,
                          pattern = "[.]converted-"), 0L)
  expect_error(download_l1000pai_data("chem", f$dir, quiet = TRUE), "overwrite = TRUE")
  expect_identical(count, 1L)
  paths <- download_l1000pai_data("chem", f$dir, overwrite = TRUE, quiet = TRUE)
  expect_identical(count, 2L)
  expect_identical(get_l1000pai_data_path("chem", f$dir), unname(paths))
}))

test_that("failed refresh preserves a previously verified library", with_synthetic_source({
  path <- register_l1000pai_data_file("chem", f$fixture, f$dir)
  old_fp <- l1000pai_content_sha256(path)$sha256
  calls <- 0L
  testthat::local_mocked_bindings(.fetch_download = function(url, destfile, http_version, timeout) {
    calls <<- calls + 1L
    writeLines("different upstream release", destfile)
    list(status_code = 200L, headers = raw())
  }, .download_sleep = function(seconds) stop("integrity mismatch must not retry"),
  .package = "L1000PAIdata")
  expect_error(download_l1000pai_data("chem", f$dir, overwrite = TRUE, quiet = TRUE),
               "does not match")
  expect_identical(calls, 1L)
  expect_identical(l1000pai_content_sha256(path)$sha256, old_fp)
  expect_identical(get_l1000pai_data_path("chem", f$dir), path)
}))

test_that("failed file promotion restores the prior complete file", with_synthetic_source({
  staged <- file.path(f$dir, "staged.txt")
  dest <- file.path(f$dir, "dest.txt")
  writeLines("new complete file", staged)
  writeLines("previous complete file", dest)
  calls <- 0L
  testthat::local_mocked_bindings(.rename_cache_file = function(from, to) {
    calls <<- calls + 1L
    if (calls %in% c(1L, 3L)) return(FALSE)
    file.rename(from, to)
  }, .package = "L1000PAIdata")
  expect_error(L1000PAIdata:::.promote_cache_file(staged, dest), "previous file was restored")
  expect_identical(readLines(dest), "previous complete file")
  expect_identical(readLines(staged), "new complete file")
  expect_length(list.files(f$dir, pattern = "[.]previous-", all.files = TRUE), 0L)
}))

test_that("synthetic source mocks are restored before later tests", {
  reference <- utils::read.csv(
    system.file("extdata", "library_sources.csv", package = "L1000PAIdata"),
    stringsAsFactors = FALSE, check.names = FALSE, na.strings = "", colClasses = "character")
  expect_identical(l1000pai_data_sources(), reference)
  expect_identical(get("l1000pai_data_sources", asNamespace("L1000PAIdata"))(), reference)
  for (name in names(original_integrity_bindings)) {
    expect_identical(get(name, asNamespace("L1000PAIdata")), original_integrity_bindings[[name]])
  }
})
