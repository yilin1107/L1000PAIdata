test_that("the source table is complete and consistent with the reference manifest", {
  src <- l1000pai_data_sources()
  man <- get_l1000pai_data_manifest()
  expect_setequal(
    src$library_id,
    c("crispr", "chem", "ligand", "oe", "single_drug", "kinase_gpcr", "kinase_gpcr_up", "kinase_gpcr_down")
  )
  expect_true(all(src$provision %in% c("download", "local_only")))
  expect_true(all(grepl("^[0-9a-f]{64}$", src$content_sha256)))
  m <- match(src$library_id, man$library_id)
  expect_false(anyNA(m))
  expect_identical(src$reference_sha256, man$sha256[m])
  expect_identical(src$cache_filename, man$filename[m])
  dl <- src[src$provision == "download", ]
  expect_true(all(nzchar(dl$upstream_library)))
  expect_true(all(grepl("^https://", dl$source_url)))
  expect_true(all(man$redistribution_status == "not_redistributed"))
})
