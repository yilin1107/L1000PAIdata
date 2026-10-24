#' Local cache directory for signature libraries
#'
#' Defaults to the per-user cache directory given by
#' `tools::R_user_dir("L1000PAIdata", "cache")`. Set the environment variable
#' `L1000PAIDATA_CACHE` or the option `L1000PAIdata.cache_dir` to use another
#' location (the option takes precedence).
#'
#' @return A directory path (not created).
#' @export
#' @examples
#' l1000pai_data_cache_dir()
l1000pai_data_cache_dir <- function() {
  opt <- getOption("L1000PAIdata.cache_dir")
  if (is.character(opt) && length(opt) == 1L && nzchar(opt)) {
    return(path.expand(opt))
  }
  env <- Sys.getenv("L1000PAIDATA_CACHE", unset = "")
  if (nzchar(env)) {
    return(path.expand(env))
  }
  tools::R_user_dir("L1000PAIdata", which = "cache")
}

.cache_paths <- function(cache_dir) {
  list(
    root = cache_dir,
    lib = file.path(cache_dir, "libraries"),
    raw = file.path(cache_dir, "raw"),
    record = file.path(cache_dir, "libraries", "download_record.csv")
  )
}

#' Download, convert and verify signature libraries
#'
#' Fetches each requested library from its public source (an Enrichr
#' gene-set library, see [l1000pai_data_sources()]), converts it to the
#' format read by `L1000PAI`, and keeps it only if its content fingerprint
#' ([l1000pai_content_sha256()]) equals that of the reference release.
#' The conversion is deterministic:
#'
#' * `enrichr_updown_suffix`: a trailing `" Up"` or `" Down"` in the signature
#'   name becomes `" up"` or `" dn"`.
#' * `enrichr_kinase_gpcr_arm`: a name of the form
#'   `"<perturbagen> <type> <time> <cell>"` becomes `"<perturbagen>(<cell>) up"`
#'   (or `dn` for the down library).
#' * `concatenate_kinase_gpcr_arms`: the converted up library followed by the
#'   converted down library.
#'
#' Blank lines are dropped and every line is written as
#' `name<TAB><TAB>gene1<TAB>...<TAB>geneN<TAB>`. The raw downloads are kept in
#' the cache for inspection.
#'
#' Downloads use verified HTTPS and at most three transfer attempts. Transient
#' connection failures and HTTP 408, 429 or 5xx responses are retried; an HTTP/2
#' framing or stream error switches subsequent attempts to a fresh HTTP/1.1
#' connection. Certificate failures, other HTTP errors and content-fingerprint
#' mismatches are not retried. Retry waits are bounded to 30 seconds; a longer
#' or non-numeric `Retry-After` response stops with an instruction to retry later.
#' Each attempt starts from an empty temporary file; incomplete transfers never
#' replace a complete cached file. The source URL and reference fingerprints
#' are unchanged by transport recovery.
#'
#' The data are provided by their upstream services under their own terms;
#' users must review the current terms at <https://maayanlab.cloud/Enrichr/>.
#' The package is for research use, not clinical decision-making, and supplies
#' no license clearance for upstream data. Cite the resources listed in the
#' package README when publishing results.
#'
#' @param library Library identifiers. Defaults to the two libraries used for
#'   paired activity inference, `"crispr"` and `"chem"`. Use `"all"` for every
#'   downloadable library.
#' @param cache_dir Cache directory; see [l1000pai_data_cache_dir()].
#' @param overwrite Logical; download again even if a verified file exists.
#'   Also replace cached raw downloads after a failed content verification.
#' @param timeout Download timeout in seconds per transfer attempt (at most
#'   three attempts per upstream file). The larger of this value and the
#'   existing R `timeout` option is used.
#' @param quiet Logical; suppress progress messages.
#'
#' @return Invisibly, a named character vector of verified file paths.
#' @export
#' @examples
#' \dontrun{
#' download_l1000pai_data(c("crispr", "chem"))
#' list_l1000pai_data_files()
#' }
download_l1000pai_data <- function(
    library = c("crispr", "chem"),
    cache_dir = l1000pai_data_cache_dir(),
    overwrite = FALSE,
    timeout = 600,
    quiet = FALSE
) {
  src <- l1000pai_data_sources()
  downloadable <- src$library_id[src$provision == "download"]
  if (identical(library, "all")) {
    library <- downloadable
  }
  bad <- setdiff(library, downloadable)
  if (length(bad)) {
    stop(
      "Not downloadable: ", paste(bad, collapse = ", "), ". ",
      "Downloadable libraries: ", paste(downloadable, collapse = ", "), ". ",
      "Libraries with provision 'local_only' can be added with register_l1000pai_data_file()."
    )
  }
  p <- .cache_paths(cache_dir)
  dir.create(p$lib, recursive = TRUE, showWarnings = FALSE)
  dir.create(p$raw, recursive = TRUE, showWarnings = FALSE)
  old <- options(timeout = max(timeout, getOption("timeout")))
  on.exit(options(old), add = TRUE)

  out <- character()
  for (lib in library) {
    row <- .source_row(lib)
    dest <- file.path(p$lib, row$cache_filename)
    if (!overwrite && file.exists(dest) && isTRUE(tryCatch(
        identical(l1000pai_content_sha256(dest)$sha256, row$content_sha256),
        error = function(e) FALSE))) {
      if (!quiet) message(lib, ": verified copy already in the cache.")
      out[[lib]] <- dest
      next
    }
    upstream <- strsplit(row$upstream_library, ";", fixed = TRUE)[[1L]]
    raw_files <- character()
    for (u in upstream) {
      raw_file <- file.path(p$raw, paste0(u, ".txt"))
      if (overwrite || !file.exists(raw_file)) {
        url <- sub("{library}", utils::URLencode(u, reserved = TRUE), row$source_url, fixed = TRUE)
        if (!quiet) message(lib, ": downloading ", u, " ...")
        .download_raw_atomic(url, raw_file)
      }
      raw_files[[u]] <- raw_file
    }
    tmp <- tempfile(pattern = ".converted-", tmpdir = p$lib, fileext = ".txt")
    on.exit(unlink(tmp), add = TRUE)
    .convert_library(row$normalization, raw_files, tmp)
    fp <- l1000pai_content_sha256(tmp)
    if (!identical(fp$sha256, row$content_sha256)) {
      unlink(tmp)
      stop(
        lib, ": the downloaded content does not match the reference release ",
        row$reference_release, " (", fp$n_terms, " signatures, fingerprint ",
        substr(fp$sha256, 1, 12), "...; expected ", row$n_terms, ", ",
        substr(row$content_sha256, 1, 12), "...). The upstream library may have ",
        "changed. The raw download is kept in ", p$raw, ". Retry with ",
        'download_l1000pai_data("', lib, '", cache_dir = <this cache>, ',
        "overwrite = TRUE) to replace the raw cache. If the mismatch persists, ",
        "use a verified reference copy; do not bypass fingerprint verification."
      )
    }
    .promote_cache_file(tmp, dest)
    .append_record(p$record, data.frame(
      library_id = lib,
      file = row$cache_filename,
      source = paste(upstream, collapse = ";"),
      raw_sha256 = paste(vapply(raw_files, .file_sha256, character(1)), collapse = ";"),
      file_sha256 = .file_sha256(dest),
      content_sha256 = fp$sha256,
      verified_against = row$reference_release,
      retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      stringsAsFactors = FALSE
    ))
    if (!quiet) message(lib, ": verified (", fp$n_terms, " signatures).")
    out[[lib]] <- dest
  }
  invisible(out)
}

# Separate network I/O from cache handling so offline tests can exercise every
# failure path without contacting upstream services.
.download_file <- function(url, destfile) {
  complete <- FALSE
  on.exit(if (!complete) unlink(destfile), add = TRUE)
  version <- 0L # CURL_HTTP_VERSION_NONE: negotiate normally.
  history <- character()
  timeout <- getOption("timeout", 600)
  for (attempt in seq_len(3L)) {
    # Never append a second response to bytes from a failed attempt.
    unlink(destfile)
    response <- tryCatch(.fetch_download(url, destfile, version, timeout),
                         error = identity)
    retryable <- FALSE
    headers <- raw()
    if (inherits(response, "error")) {
      is_http2 <- inherits(response, c("curl_error_http2", "curl_error_http2_stream"))
      retryable <- is_http2 || inherits(response, c(
        "curl_error_couldnt_resolve_proxy", "curl_error_couldnt_resolve_host",
        "curl_error_couldnt_connect", "curl_error_operation_timedout",
        "curl_error_send_error", "curl_error_recv_error", "curl_error_got_nothing",
        "curl_error_partial_file"))
      reason <- conditionMessage(response)
      if (is_http2) {
        version <- 2L # CURL_HTTP_VERSION_1_1, not the numeric version 1.1.
        reason <- paste0(reason, "; subsequent attempt uses fresh HTTPS/HTTP/1.1")
      }
    } else {
      status <- response$status_code
      headers <- response$headers
      if (identical(as.integer(status), 200L) && file.exists(destfile) &&
          isTRUE(file.info(destfile)$size > 0)) {
        complete <- TRUE
        return(0L)
      }
      retryable <- length(status) == 1L && !is.na(status) &&
        (status %in% c(408L, 429L) || (status >= 500L && status <= 599L))
      reason <- paste0("HTTP ", paste(status, collapse = ","),
                       "; no complete non-empty HTTP 200 response")
    }
    history <- c(history, paste0("attempt ", attempt, ": ", reason))
    if (!retryable || attempt == 3L) break
    delay <- .download_retry_delay(headers, attempt)
    if (is.na(delay)) {
      history <- c(history, "Retry-After requires a later retry; automatic wait is limited to 30 seconds")
      break
    }
    .download_sleep(delay)
  }
  stop(paste(history, collapse = " | "), call. = FALSE)
}

# Private transport and sleep seams keep offline regression tests deterministic.
.fetch_download <- function(url, destfile, http_version, timeout) {
  handle <- curl::new_handle(
    http_version = http_version, fresh_connect = TRUE, followlocation = TRUE,
    failonerror = FALSE,
    maxredirs = 5L, timeout = timeout, connecttimeout = min(30, timeout),
    ssl_verifypeer = TRUE, ssl_verifyhost = 2L,
    protocols = 2L, redir_protocols = 2L # HTTPS only, including redirects.
  )
  curl::curl_fetch_disk(url, destfile, handle = handle)
}

.download_sleep <- function(seconds) Sys.sleep(seconds)

.download_retry_delay <- function(headers, attempt) {
  wait <- min(2^(attempt - 1L), 30)
  if (is.null(headers) || !length(headers)) return(wait)
  lines <- strsplit(if (is.raw(headers)) rawToChar(headers) else headers,
                    "\r?\n")[[1L]]
  after <- grep("^retry-after:", lines, ignore.case = TRUE, value = TRUE)
  if (!length(after)) return(wait)
  after <- trimws(sub("^[^:]+:", "", utils::tail(after, 1L)))
  # HTTP-date and waits over the bound require an explicit later user retry.
  if (!grepl("^[0-9]+$", after)) return(NA_real_)
  after <- as.numeric(after)
  if (!is.finite(after) || after > 30) return(NA_real_)
  max(wait, after)
}

.download_raw_atomic <- function(url, dest) {
  tmp <- tempfile(pattern = ".download-", tmpdir = dirname(dest), fileext = ".part")
  on.exit(unlink(tmp), add = TRUE)
  status <- tryCatch(.download_file(url, tmp), error = function(e) {
    stop("Download failed for ", url, ": ", conditionMessage(e),
         ". The previous raw cache was not changed; retry with overwrite = TRUE.")
  })
  if (length(status) != 1L || is.na(status) || !is.numeric(status) || status != 0 ||
      !file.exists(tmp) || is.na(file.info(tmp)$size) || file.info(tmp)$size == 0) {
    stop("Download failed for ", url,
         ". No complete non-empty file was returned; the previous raw cache ",
         "was not changed. Retry with overwrite = TRUE.")
  }
  .promote_cache_file(tmp, dest)
  invisible(dest)
}

.rename_cache_file <- function(from, to) file.rename(from, to)

.promote_cache_file <- function(staged, dest) {
  if (suppressWarnings(.rename_cache_file(staged, dest))) return(invisible(dest))
  # Windows may not rename over an existing file. Keep a recoverable backup
  # until the complete staged file is in place; never truncate the old file.
  if (!file.exists(dest) || dir.exists(dest)) stop("Could not write ", dest, ".")
  backup <- tempfile(pattern = ".previous-", tmpdir = dirname(dest))
  if (!suppressWarnings(.rename_cache_file(dest, backup))) {
    stop("Could not replace ", dest, "; the previous file was not changed.")
  }
  if (!suppressWarnings(.rename_cache_file(staged, dest))) {
    restored <- suppressWarnings(.rename_cache_file(backup, dest))
    stop("Could not write ", dest, ". ", if (restored) {
      "The previous file was restored."
    } else paste0("The previous file is preserved at ", backup, "."))
  }
  unlink(backup)
  invisible(dest)
}

#' Add a library from a local file
#'
#' Copies a local library file into the cache after checking that its content
#' fingerprint equals the reference release. This is the way to provide the
#' `"local_only"` libraries (`ligand`, `oe`, `single_drug`) from an existing
#' copy, and it also accepts local copies of downloadable libraries.
#'
#' @param library One library identifier from [l1000pai_data_sources()].
#' @param path Path to the local file.
#' @param cache_dir Cache directory; see [l1000pai_data_cache_dir()].
#'
#' @return Invisibly, the cached file path.
#' @export
register_l1000pai_data_file <- function(library, path, cache_dir = l1000pai_data_cache_dir()) {
  row <- .source_row(library)
  fp <- l1000pai_content_sha256(path)
  if (!identical(fp$sha256, row$content_sha256)) {
    stop(
      library, ": the file's content does not match the reference release ",
      row$reference_release, " (", fp$n_terms, " signatures; expected ", row$n_terms, ")."
    )
  }
  p <- .cache_paths(cache_dir)
  dir.create(p$lib, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(p$lib, row$cache_filename)
  if (!identical(normalizePath(path, mustWork = TRUE), normalizePath(dest, mustWork = FALSE))) {
    tmp <- tempfile(pattern = ".register-", tmpdir = p$lib, fileext = ".txt")
    on.exit(unlink(tmp), add = TRUE)
    if (!file.copy(path, tmp)) stop("Could not stage a local copy for ", dest, ".")
    .verify_cached_path(tmp, row)
    .promote_cache_file(tmp, dest)
  }
  .append_record(p$record, data.frame(
    library_id = library,
    file = row$cache_filename,
    source = paste0("local:", basename(path)),
    raw_sha256 = .file_sha256(path),
    file_sha256 = .file_sha256(dest),
    content_sha256 = fp$sha256,
    verified_against = row$reference_release,
    retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    stringsAsFactors = FALSE
  ))
  invisible(dest)
}

.file_sha256 <- function(path) {
  digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)
}

.append_record <- function(path, rec) {
  if (file.exists(path)) {
    old <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
    old <- old[old$library_id != rec$library_id, , drop = FALSE]
    rec <- rbind(old, rec)
  }
  utils::write.csv(rec, path, row.names = FALSE)
}

.read_lines_utf8 <- function(path) {
  x <- readLines(path, encoding = "UTF-8", warn = FALSE)
  x <- sub("\r$", "", x)
  x[nzchar(gsub("\t", "", x, fixed = TRUE))]
}

.rename_lines <- function(lines, fun) {
  fields <- strsplit(lines, "\t", fixed = TRUE)
  vapply(fields, function(f) {
    rest <- if (length(f) > 1L) f[-1L] else ""
    paste0(paste(c(fun(f[[1L]]), rest), collapse = "\t"), "\t")
  }, character(1))
}

.rename_updown <- function(name) {
  name <- sub(" Up$", " up", name)
  sub(" Down$", " dn", name)
}

.rename_kinase_gpcr <- function(suffix) {
  function(name) {
    m <- regmatches(name, regexec("^(.+?) (\\S+) (\\S+) (\\S+)$", name))[[1L]]
    if (length(m) != 5L) {
      stop("Unexpected kinase/GPCR signature name: ", name)
    }
    paste0(m[[2L]], "(", m[[5L]], ") ", suffix)
  }
}

.convert_library <- function(rule, raw_files, dest) {
  out <- switch(
    rule,
    enrichr_updown_suffix = .rename_lines(.read_lines_utf8(raw_files[[1L]]), .rename_updown),
    enrichr_kinase_gpcr_arm = {
      suffix <- if (grepl("_down$", names(raw_files)[[1L]])) "dn" else "up"
      .rename_lines(.read_lines_utf8(raw_files[[1L]]), .rename_kinase_gpcr(suffix))
    },
    concatenate_kinase_gpcr_arms = {
      up <- raw_files[grepl("_up$", names(raw_files))]
      dn <- raw_files[grepl("_down$", names(raw_files))]
      c(
        .rename_lines(.read_lines_utf8(up[[1L]]), .rename_kinase_gpcr("up")),
        .rename_lines(.read_lines_utf8(dn[[1L]]), .rename_kinase_gpcr("dn"))
      )
    },
    stop("Unknown conversion rule: ", rule)
  )
  con <- file(dest, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(out, collapse = "\n"))), con)
  writeBin(charToRaw("\n"), con)
  invisible(dest)
}
