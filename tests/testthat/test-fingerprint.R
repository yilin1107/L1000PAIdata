test_that("the content fingerprint ignores layout but not content", {
  a <- tempfile(); b <- tempfile(); d <- tempfile()
  writeLines(c("A up\t\tG2\tG1\t", "A dn\t\tG3", ""), a)
  writeLines(c("A dn\tdescription\tG3\t\t", "A up\t\tG1\tG2"), b)
  writeLines(c("A up\t\tG1\tG2", "A dn\t\tG4"), d)
  fa <- l1000pai_content_sha256(a)
  expect_identical(fa$n_terms, 2L)
  expect_identical(fa$sha256, l1000pai_content_sha256(b)$sha256)
  expect_false(identical(fa$sha256, l1000pai_content_sha256(d)$sha256))
  expect_match(fa$sha256, "^[0-9a-f]{64}$")
})

test_that("the fingerprint matches its documented definition", {
  f <- tempfile()
  writeLines(c("B dn\t\tY\tX", "A up\t\tG2\tG1"), f)
  expected <- digest::digest(charToRaw("A up\tG1\tG2\nB dn\tX\tY"), algo = "sha256", serialize = FALSE)
  expect_identical(l1000pai_content_sha256(f)$sha256, expected)
})
