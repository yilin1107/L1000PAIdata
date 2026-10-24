# L1000PAIdata governance contract

## Reference release and distribution

The library files used for the L1000PAI analyses are the reference release
`legacy-local-2026-08-08`; their byte-level manifest is
`inst/extdata/library_manifest.csv`. The files are not redistributed.

Since version 1.0.0, `download_l1000pai_data()` obtains the `crispr`, `chem`
and kinase/GPCR libraries from their public Enrichr source, converts them by a
documented renaming rule, and accepts them only when their content fingerprint
equals that of the reference release (`inst/extdata/library_sources.csv`).
The `ligand`, `oe` and `single_drug` libraries have no confirmed upstream
source; they can be registered from a local copy whose content fingerprint
matches the reference.

Exactly five library identifiers are downloadable: `crispr`, `chem`,
`kinase_gpcr`, `kinase_gpcr_up` and `kinase_gpcr_down`. The last three include
a combined library and its two arms, not three independent perturbation sources.
The other three identifiers remain local-only; eight-library public
reproducibility is not claimed. This research-use package is not a clinical
decision tool. Users must review current upstream terms at
<https://maayanlab.cloud/Enrichr/> and <https://lincsproject.org/>. Fingerprint
verification establishes content identity, not data ownership, license
clearance, or redistribution permission. Unresolved provenance fields are
retained as unresolved.

Provider access recomputes the requested library's content fingerprint on each
read. Listing verifies present libraries by default; an explicitly unverified
inventory is not analysis-ready input. Interrupted downloads are staged and
discarded, while previous complete files are retained. Content mismatches do
not replace a verified library and must be resolved by refreshing the raw cache
with `overwrite = TRUE` or registering a reference-matching local copy; the
expected fingerprint must never be relaxed to accept changed upstream content.

## Required future signature schema

A normalized release must stop using display names as signature identifiers.
It should include two linked tables:

### signatures

- `signature_id` (globally unique)
- `library_id` and `data_release_id`
- `pair_id`
- `perturbagen_id` and `perturbagen_label`
- `perturbation_type`
- `direction` (`up`, `down`, or `single`)
- `organism_taxid`
- `gene_id_namespace` and namespace version
- `cell_id`
- dose value and unit
- time value and unit
- replicate or consensus identifier
- upstream source-record identifier

### signature_genes

- `signature_id`
- `gene_id`
- rank/order when the upstream semantics support it

Duplicate display names must never cause rows from different cell, dose, time
or replicate contexts to be silently unioned.

## Build pipeline

```text
fetch immutable raw input
  -> verify upstream checksum
  -> parse while preserving source metadata
  -> normalize to a new output (never in-place)
  -> validate schema and pair completeness
  -> build deterministic artifacts
  -> publish with manifest and checksums
```

The existing in-place normalization script is retained only for historical
audit and must not be used in the new pipeline.

## Public release gate

Every distributed artifact must have:

- confirmed source URL or accession and access date;
- upstream version and citation;
- reviewed license/terms and redistribution decision;
- SHA-256 checksum and byte size;
- organism and gene identifier namespace;
- transformation lineage and deterministic build command;
- structural validation, duplicate policy and known-issue record;
- an exact data release identifier and manifest schema version.

Any unresolved provenance or license field blocks public redistribution.
