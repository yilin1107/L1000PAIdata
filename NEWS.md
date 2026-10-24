# L1000PAIdata 1.0.0

- Candidate revision 3 (unreleased): use `curl` for typed transport failures.
  HTTP/2 framing/stream failures retry on a fresh HTTP/1.1 connection, without
  changing HTTPS verification, source URLs or reference fingerprints. Transient
  network failures and HTTP 408/429/5xx responses have at most three attempts;
  certificate failures, other HTTP errors and content mismatches are not retried.
  Partial responses are discarded before each retry. Offline regression tests
  cover protocol fallback, retry bounds, Retry-After and cache preservation.
- Revalidate cached content on each requested-library access. A prior download
  or registration no longer allows a subsequently modified cache file to pass
  silently. Inventory listing verifies present files by default; the explicit
  `verify_hash = FALSE` inventory option must not be used for analysis input.
- Stage downloads and local registration in temporary files before promoting
  complete verified files. Failed or interrupted transfers preserve previous
  files; reference mismatches provide an explicit raw-cache refresh instruction.
- Added offline synthetic regression tests for cache tampering, successful
  registration, interrupted transfers, mismatch/retry handling and rollback.
- Clarified that five identifiers are downloadable and three are local-only;
  the package is research-only and grants no upstream data license clearance.
- The package no longer contains signature data. `download_l1000pai_data()`
  fetches the `crispr`, `chem` and kinase/GPCR libraries from their Enrichr
  source, converts them to the L1000PAI format and accepts them only when
  their content fingerprint matches the reference release
  `legacy-local-2026-08-08`. Analyses run on downloaded and reference files
  give identical results.
- Added `l1000pai_data_sources()`, `l1000pai_content_sha256()`,
  `l1000pai_data_cache_dir()` and `register_l1000pai_data_file()`.
- `list_l1000pai_data_files()`, `get_l1000pai_data_path()`,
  `get_kinase_gpcr_paths()` and `verify_l1000pai_data_files()` now work on
  the local cache.
- The reference manifest records the source of each downloadable library.

# L1000PAIdata 0.1.0.9000

- Established the first versioned companion-package contract for L1000PAI.
- Added a generated artifact manifest with SHA-256 hashes, byte sizes and
  signature-level quality counts.
- Added manifest access and optional file-verification helpers.
- Added a data-governance contract for immutable raw inputs, unique signature
  identifiers and external distribution of large assets.

# L1000PAIdata 0.0.0.9000

- Initialized the data package skeleton for L1000 perturbation signature
  libraries.
- Added helper functions for listing and retrieving library file paths.
