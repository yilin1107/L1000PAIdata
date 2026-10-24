test_that("Enrichr names are converted as documented", {
  expect_identical(L1000PAIdata:::.rename_updown("TP53 Up"), "TP53 up")
  expect_identical(L1000PAIdata:::.rename_updown("TP53 Down"), "TP53 dn")
  expect_identical(L1000PAIdata:::.rename_updown("Down Upstream"), "Down Upstream")
  f <- L1000PAIdata:::.rename_kinase_gpcr("dn")
  expect_identical(f("ABCF1 knockdown 96h A375"), "ABCF1(A375) dn")
  expect_error(f("ABCF1"), "Unexpected")
})

test_that("conversion writes the L1000PAI line format and drops blank lines", {
  raw <- tempfile(); out <- tempfile()
  writeLines(c("A1BG Up\t\tG1\tG2", "A1BG Down\t\tG3", "\t\t"), raw)
  L1000PAIdata:::.convert_library("enrichr_updown_suffix", c(X = raw), out)
  expect_identical(readLines(out), c("A1BG up\t\tG1\tG2\t", "A1BG dn\t\tG3\t"))
})

test_that("an empty cache lists nothing and gives an actionable error", {
  dir <- tempfile("cache")
  expect_length(list_l1000pai_data_files(dir), 0L)
  expect_error(get_l1000pai_data_path("crispr", dir), "download_l1000pai_data")
  expect_error(get_l1000pai_data_path("oe", dir), "register_l1000pai_data_file")
  v <- verify_l1000pai_data_files(cache_dir = dir)
  expect_false(any(v$exists))
})

test_that("register refuses a file whose content differs from the reference", {
  f <- tempfile()
  writeLines("A up\t\tG1", f)
  expect_error(register_l1000pai_data_file("crispr", f, tempfile("cache")), "does not match")
})

test_that("the cache directory honours the option and the environment variable", {
  withr_opt <- options(L1000PAIdata.cache_dir = "/tmp/x_opt")
  on.exit(options(withr_opt))
  expect_identical(l1000pai_data_cache_dir(), "/tmp/x_opt")
  options(L1000PAIdata.cache_dir = NULL)
  old <- Sys.getenv("L1000PAIDATA_CACHE")
  Sys.setenv(L1000PAIDATA_CACHE = "/tmp/x_env")
  on.exit(Sys.setenv(L1000PAIDATA_CACHE = old), add = TRUE)
  expect_identical(l1000pai_data_cache_dir(), "/tmp/x_env")
})

test_that("downloaded libraries reproduce the reference release", {
  skip_on_cran()
  skip_if_not(identical(Sys.getenv("L1000PAIDATA_TEST_DOWNLOAD"), "true"),
              "set L1000PAIDATA_TEST_DOWNLOAD=true to run the download test")
  dir <- tempfile("cache")
  paths <- download_l1000pai_data("all", cache_dir = dir, quiet = TRUE)
  expect_setequal(names(paths), c("crispr", "chem", "kinase_gpcr", "kinase_gpcr_up", "kinase_gpcr_down"))
  v <- verify_l1000pai_data_files(cache_dir = dir)
  expect_true(all(v$ok[v$exists]))
})
