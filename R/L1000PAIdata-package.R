#' L1000PAIdata: signature libraries for L1000PAI
#'
#' `L1000PAIdata` supplies the L1000 perturbation signature libraries used by
#' the `L1000PAI` package. The libraries are not distributed with the package.
#' [download_l1000pai_data()] fetches them from their public source, converts
#' them to the format `L1000PAI` reads, and accepts a file only when its content
#' fingerprint matches the reference release recorded in
#' [l1000pai_data_sources()]. Verified files are kept in a local cache
#' ([l1000pai_data_cache_dir()]) and exposed to `L1000PAI` through
#' [list_l1000pai_data_files()].
#'
#' Use of the downloaded data is governed by the terms of the upstream
#' providers (see the package README); the MIT license of this
#' package covers its code only.
#'
#' @keywords internal
"_PACKAGE"
