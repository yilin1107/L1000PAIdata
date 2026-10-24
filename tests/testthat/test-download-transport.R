# No network requests or real sleeps occur in this file.
transport_error <- function(type, message = "synthetic transfer failure") {
  structure(list(message = message, call = NULL),
            class = c(paste0("curl_error_", type), "curl_error", "error", "condition"))
}

with_transport_fixture <- function(code) {
  dir <- tempfile("transport-test-")
  dir.create(dir)
  dest <- file.path(dir, "complete.txt")
  writeLines("previous complete content", dest)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  eval(substitute(code), envir = environment())
}

test_that("successful HTTPS transport needs only one negotiated attempt", with_transport_fixture({
  seen <- list()
  testthat::local_mocked_bindings(
    .fetch_download = function(url, destfile, http_version, timeout) {
      seen[[length(seen) + 1L]] <<- list(url, http_version, timeout)
      writeLines("new complete content", destfile)
      list(status_code = 200L, headers = raw())
    }, .download_sleep = function(seconds) stop("unexpected retry"),
    .package = "L1000PAIdata")
  L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest)
  expect_length(seen, 1L)
  expect_identical(seen[[1L]][[2L]], 0L)
  expect_identical(readLines(dest), "new complete content")
}))

test_that("HTTP2 framing and stream errors fall back to clean HTTP1.1 attempts", with_transport_fixture({
  for (type in c("http2", "http2_stream")) {
    versions <- integer()
    waits <- numeric()
    starts_empty <- logical()
    testthat::local_mocked_bindings(
      .fetch_download = function(url, destfile, http_version, timeout) {
        versions <<- c(versions, http_version)
        starts_empty <<- c(starts_empty, !file.exists(destfile))
        if (length(versions) == 1L) {
          writeLines("partial first response", destfile)
          stop(transport_error(type, "Stream error in HTTP/2 framing layer"))
        }
        writeLines("new complete content", destfile)
        list(status_code = 200L, headers = raw())
      }, .download_sleep = function(seconds) waits <<- c(waits, seconds),
      .package = "L1000PAIdata")
    L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest)
    expect_identical(versions, c(0L, 2L))
    expect_identical(starts_empty, c(TRUE, TRUE))
    expect_equal(waits, 1)
    expect_identical(readLines(dest), "new complete content")
    expect_length(list.files(dir, pattern = "[.]part$", all.files = TRUE), 0L)
  }
}))

test_that("repeated transient failures are bounded and preserve old raw content", with_transport_fixture({
  versions <- integer()
  waits <- numeric()
  testthat::local_mocked_bindings(
    .fetch_download = function(url, destfile, http_version, timeout) {
      versions <<- c(versions, http_version)
      writeLines("partial", destfile)
      stop(transport_error("http2_stream"))
    }, .download_sleep = function(seconds) waits <<- c(waits, seconds),
    .package = "L1000PAIdata")
  expect_error(L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest),
               "attempt 3")
  expect_identical(versions, c(0L, 2L, 2L))
  expect_equal(waits, c(1, 2))
  expect_identical(readLines(dest), "previous complete content")
  expect_length(list.files(dir, pattern = "[.]part$", all.files = TRUE), 0L)
}))

test_that("other transient transport errors retry without changing protocol", with_transport_fixture({
  for (type in c("couldnt_resolve_proxy", "couldnt_resolve_host", "couldnt_connect",
                 "operation_timedout", "send_error", "recv_error", "got_nothing",
                 "partial_file")) {
    versions <- integer()
    testthat::local_mocked_bindings(
      .fetch_download = function(url, destfile, http_version, timeout) {
        versions <<- c(versions, http_version)
        writeLines("complete response", destfile)
        if (length(versions) == 1L) stop(transport_error(type))
        list(status_code = 200L, headers = raw())
      }, .download_sleep = function(seconds) NULL, .package = "L1000PAIdata")
    L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest)
    expect_identical(versions, c(0L, 0L))
    expect_identical(readLines(dest), "complete response")
  }
}))

test_that("certificate and local-write failures are never retried", with_transport_fixture({
  for (type in c("peer_failed_verification", "ssl_connect_error", "write_error",
                 "url_malformat", "unsupported_protocol")) {
    calls <- 0L
    testthat::local_mocked_bindings(
      .fetch_download = function(url, destfile, http_version, timeout) {
        calls <<- calls + 1L
        stop(transport_error(type))
      }, .download_sleep = function(seconds) stop("unexpected retry"),
      .package = "L1000PAIdata")
    expect_error(L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest),
                 "previous raw cache was not changed")
    expect_identical(calls, 1L)
    expect_identical(readLines(dest), "previous complete content")
  }
}))

test_that("HTTP408,429 and server failures retry but other responses do not", with_transport_fixture({
  for (status in c(408L, 429L, 500L, 503L, 599L)) {
    calls <- 0L
    testthat::local_mocked_bindings(
      .fetch_download = function(url, destfile, http_version, timeout) {
        calls <<- calls + 1L
        writeLines(if (calls == 1L) "error body" else "complete", destfile)
        list(status_code = if (calls == 1L) status else 200L, headers = raw())
      }, .download_sleep = function(seconds) NULL, .package = "L1000PAIdata")
    L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest)
    expect_identical(calls, 2L)
    expect_identical(readLines(dest), "complete")
  }
  for (status in c(206L, 302L, 400L, 401L, 403L, 404L, 410L)) {
    writeLines("previous complete content", dest)
    calls <- 0L
    testthat::local_mocked_bindings(
      .fetch_download = function(url, destfile, http_version, timeout) {
        calls <<- calls + 1L
        writeLines("partial or error body", destfile)
        list(status_code = status, headers = raw())
      }, .download_sleep = function(seconds) stop("unexpected retry"),
      .package = "L1000PAIdata")
    expect_error(L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest),
                 paste0("HTTP ", status))
    expect_identical(calls, 1L)
    expect_identical(readLines(dest), "previous complete content")
    expect_length(list.files(dir, pattern = "[.]part$", all.files = TRUE), 0L)
  }
}))

test_that("Retry-After is honored within the wait bound and stops beyond it", with_transport_fixture({
  calls <- 0L
  waits <- numeric()
  header <- "HTTP/2 429\r\nRetry-After: 3\r\n"
  testthat::local_mocked_bindings(
    .fetch_download = function(url, destfile, http_version, timeout) {
      calls <<- calls + 1L
      writeLines("complete", destfile)
      list(status_code = if (calls == 1L) 429L else 200L,
           headers = charToRaw(header))
    }, .download_sleep = function(seconds) waits <<- c(waits, seconds),
    .package = "L1000PAIdata")
  L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest)
  expect_equal(waits, 3)
  expect_identical(calls, 2L)
  for (value in c("120", "Fri, 23 Oct 2026 12:00:00 GMT", "not-a-delay")) {
    calls <- 0L
    waits <- numeric()
    header <- paste0("HTTP/2 429\r\nRetry-After: ", value, "\r\n")
    expect_error(L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest),
                 "automatic wait is limited to 30 seconds")
    expect_identical(calls, 1L)
    expect_length(waits, 0L)
  }
}))

test_that("empty HTTP200 responses and untyped errors fail safely", with_transport_fixture({
  for (mode in c("empty", "missing", "untyped")) {
    calls <- 0L
    testthat::local_mocked_bindings(
      .fetch_download = function(url, destfile, http_version, timeout) {
        calls <<- calls + 1L
        if (mode == "untyped") stop("unexpected local failure")
        if (mode == "empty") writeLines(character(), destfile)
        list(status_code = 200L, headers = raw())
      }, .download_sleep = function(seconds) stop("unexpected retry"),
      .package = "L1000PAIdata")
    expect_error(L1000PAIdata:::.download_raw_atomic("https://synthetic.invalid", dest),
                 "Download failed")
    expect_identical(calls, 1L)
    expect_identical(readLines(dest), "previous complete content")
    expect_length(list.files(dir, pattern = "[.]part$", all.files = TRUE), 0L)
  }
}))
