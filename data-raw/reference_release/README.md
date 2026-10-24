# Reference release `legacy-local-2026-08-08`

These scripts produced the reference library files used for the L1000PAI
analyses and are kept as a record of how they were made.

- `normalize_extdata_signature_names.py` renamed the signatures of the
  downloaded Enrichr libraries in place (`" Up"`/`" Down"` to `" up"`/`" dn"`,
  kinase/GPCR names to `"<gene>(<cell>) up|dn"`) and concatenated the
  kinase/GPCR arms. `download_l1000pai_data()` applies the same renaming to a
  fresh download and verifies the result by content fingerprint.
- `build_library_manifest.py` wrote `inst/extdata/library_manifest.csv` from the
  local files. Since version 1.0.0 the manifest also records the confirmed
  source of each downloadable library; re-running the script would reset those
  fields to their 2026-08 values.

Neither script is needed to use the package.
