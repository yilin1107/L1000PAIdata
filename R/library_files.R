#' List verified library files in the cache
#'
#' The provider interface used by `L1000PAI::get_l1000_library()`. Returns the
#' libraries present in the cache, after verifying their content fingerprints;
#' run [download_l1000pai_data()] (or
#' [register_l1000pai_data_file()]) first.
#'
#' @param cache_dir Cache directory; see [l1000pai_data_cache_dir()].
#' @param verify_hash Logical; verify every present file (the default). Set to
#'   `FALSE` only for an unverified inventory, never to supply analysis data.
#'
#' @return A named character vector of file paths (possibly empty).
#' @export
#' @examples
#' list_l1000pai_data_files()
list_l1000pai_data_files <- function(cache_dir = l1000pai_data_cache_dir(), verify_hash = TRUE) {
  .check_flag(verify_hash, "verify_hash")
  src <- l1000pai_data_sources()
  paths <- file.path(.cache_paths(cache_dir)$lib, src$cache_filename)
  present <- file.exists(paths)
  if (verify_hash) {
    for (i in which(present)) .verify_cached_path(paths[[i]], src[i, , drop = FALSE])
  }
  structure(paths[present], names = src$library_id[present])
}

#' Path of one cached library
#'
#' @param library One of `"crispr"`, `"chem"`, `"ligand"`, `"oe"`,
#'   `"single_drug"`, `"kinase_gpcr"`, `"kinase_gpcr_up"` or
#'   `"kinase_gpcr_down"`.
#' @param cache_dir Cache directory; see [l1000pai_data_cache_dir()].
#'
#' @details The requested file is re-fingerprinted on every access. Other
#'   libraries are not checked by this function. A corrupted file is rejected
#'   with a repair instruction; prior registration is not proof of integrity.
#'
#' @return A file path.
#' @export
get_l1000pai_data_path <- function(
    library = c("crispr", "chem", "ligand", "oe", "single_drug",
                "kinase_gpcr", "kinase_gpcr_up", "kinase_gpcr_down"),
    cache_dir = l1000pai_data_cache_dir()
) {
  library <- match.arg(library)
  row <- .source_row(library)
  path <- file.path(.cache_paths(cache_dir)$lib, row$cache_filename)
  if (!file.exists(path)) {
    hint <- if (identical(row$provision, "download")) {
      paste0('Run L1000PAIdata::download_l1000pai_data("', library, '") first.')
    } else {
      paste0('Add a local copy with L1000PAIdata::register_l1000pai_data_file("', library, '", path).')
    }
    stop("Library `", library, "` is not in the cache (", cache_dir, "). ", hint)
  }
  .verify_cached_path(path, row)
  unname(path)
}

.check_flag <- function(value, name) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    stop("`", name, "` must be TRUE or FALSE.")
  }
}

.cache_repair_hint <- function(row) {
  if (identical(row$provision, "download")) {
    paste0('Run download_l1000pai_data("', row$library_id,
           '", cache_dir = <this cache>, overwrite = TRUE) to retry from upstream; ',
           'a changed upstream library still must match the reference fingerprint.')
  } else {
    paste0('Register a verified local copy with register_l1000pai_data_file("',
           row$library_id, '", path, cache_dir = <this cache>).')
  }
}

.verify_cached_path <- function(path, row) {
  observed <- tryCatch(l1000pai_content_sha256(path)$sha256, error = function(e) NA_character_)
  if (!identical(observed, row$content_sha256)) {
    stop("Cached library `", row$library_id, "` failed content verification: ", path,
         ". The file may be corrupted or modified. ", .cache_repair_hint(row))
  }
  invisible(path)
}

#' Paths of the kinase/GPCR libraries
#'
#' @param cache_dir Cache directory; see [l1000pai_data_cache_dir()].
#'
#' @return A named character vector with `consensus`, `up` and `down` paths.
#' @export
get_kinase_gpcr_paths <- function(cache_dir = l1000pai_data_cache_dir()) {
  c(
    consensus = get_l1000pai_data_path("kinase_gpcr", cache_dir),
    up = get_l1000pai_data_path("kinase_gpcr_up", cache_dir),
    down = get_l1000pai_data_path("kinase_gpcr_down", cache_dir)
  )
}

#' Verify cached library files
#'
#' Checks that each cached library exists and, by default, that its content
#' fingerprint still equals the reference release.
#'
#' @param verify_hash Logical; recompute content fingerprints.
#' @param stop_on_error Logical; stop if any cached file fails.
#' @param cache_dir Cache directory; see [l1000pai_data_cache_dir()].
#'
#' @return A data frame with one row per library.
#' @export
verify_l1000pai_data_files <- function(
    verify_hash = TRUE,
    stop_on_error = TRUE,
    cache_dir = l1000pai_data_cache_dir()
) {
  .check_flag(verify_hash, "verify_hash")
  .check_flag(stop_on_error, "stop_on_error")
  src <- l1000pai_data_sources()
  paths <- file.path(.cache_paths(cache_dir)$lib, src$cache_filename)
  exists <- file.exists(paths)
  observed <- rep(NA_character_, length(paths))
  if (verify_hash) {
    observed[exists] <- vapply(paths[exists], function(f) {
      tryCatch(l1000pai_content_sha256(f)$sha256, error = function(e) NA_character_)
    }, character(1))
  }
  matches <- ifelse(exists & verify_hash, observed == src$content_sha256, NA)
  result <- data.frame(
    library_id = src$library_id,
    provision = src$provision,
    path = paths,
    exists = exists,
    content_sha256 = observed,
    matches_reference = matches,
    ok = exists & (!verify_hash | (!is.na(matches) & matches)),
    stringsAsFactors = FALSE
  )
  failed <- result$exists & !result$ok
  if (stop_on_error && any(failed)) {
    details <- vapply(which(failed), function(i) {
      paste0(result$library_id[[i]], ": ", .cache_repair_hint(src[i, , drop = FALSE]))
    }, character(1))
    stop("Cached library failed verification: ", paste(details, collapse = "\n"))
  }
  result
}
