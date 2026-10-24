#' Signature-library sources and reference fingerprints
#'
#' One row per library. `provision` is `"download"` for libraries that
#' [download_l1000pai_data()] can fetch, and `"local_only"` for libraries whose
#' upstream source is unconfirmed; those can be added from a local copy with
#' [register_l1000pai_data_file()].
#'
#' `content_sha256` is the content fingerprint (see [l1000pai_content_sha256()])
#' of the reference release `reference_release`, the library files used for the
#' L1000PAI analyses. `reference_sha256` and `reference_bytes` describe the
#' reference files byte for byte. `upstream_sha256_observed` records the raw
#' download observed on `upstream_observed_utc`; it is informational, because
#' the upstream service may reorder genes within a signature without changing
#' its content.
#'
#' @return A data frame.
#' @export
#' @examples
#' l1000pai_data_sources()[, c("library_id", "provision", "n_terms")]
l1000pai_data_sources <- function() {
  path <- system.file("extdata", "library_sources.csv", package = "L1000PAIdata")
  if (identical(path, "")) {
    stop("The L1000PAIdata source table was not found.")
  }
  utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    na.strings = "",
    colClasses = "character"
  )
}

#' Reference-release manifest of the original library files
#'
#' The byte-level manifest (size, SHA-256, counts) of the library files used
#' for the L1000PAI analyses, release `legacy-local-2026-08-08`. The files
#' themselves are not distributed; the manifest documents what
#' [download_l1000pai_data()] reproduces.
#'
#' @return A data frame with one row per reference file.
#' @export
get_l1000pai_data_manifest <- function() {
  path <- system.file("extdata", "library_manifest.csv", package = "L1000PAIdata")
  if (identical(path, "")) {
    stop("The L1000PAIdata reference manifest was not found.")
  }
  utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    na.strings = c("")
  )
}

.source_row <- function(library) {
  src <- l1000pai_data_sources()
  if (!library %in% src$library_id) {
    stop(
      "Unknown library `", library, "`. Known libraries: ",
      paste(src$library_id, collapse = ", "), "."
    )
  }
  src[src$library_id == library, , drop = FALSE]
}
