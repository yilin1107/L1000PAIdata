#' Content fingerprint of a signature-library file
#'
#' A SHA-256 fingerprint that depends only on what each signature contains, not
#' on how the file is laid out. For every non-blank line, the signature name
#' (first field) is joined by a tab to its genes (third field onward, empty
#' fields dropped) sorted in byte order; these lines are sorted in byte order,
#' joined by newlines without a trailing newline, and hashed as UTF-8.
#' The description field (second field), gene order within a signature, line
#' order and line endings therefore do not affect the fingerprint.
#'
#' @param path Path to a GMT-like tab-separated library file.
#'
#' @return A list with `sha256` (character) and `n_terms` (integer).
#' @export
#' @examples
#' f <- tempfile()
#' writeLines(c("A up\t\tG2\tG1", "A dn\t\tG3"), f)
#' l1000pai_content_sha256(f)
l1000pai_content_sha256 <- function(path) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    stop("`path` must be one existing file.")
  }
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  lines <- sub("\r$", "", lines)
  lines <- lines[nzchar(gsub("\t", "", lines, fixed = TRUE))]
  fields <- strsplit(lines, "\t", fixed = TRUE)
  rows <- vapply(fields, function(f) {
    genes <- if (length(f) > 2L) f[-(1:2)] else character()
    genes <- genes[nzchar(genes)]
    genes <- sort(genes, method = "radix")
    paste(c(f[[1L]], paste(genes, collapse = "\t")), collapse = "\t")
  }, character(1))
  rows <- sort(enc2utf8(rows), method = "radix")
  text <- paste(rows, collapse = "\n")
  list(
    sha256 = digest::digest(charToRaw(enc2utf8(text)), algo = "sha256", serialize = FALSE),
    n_terms = length(rows)
  )
}
