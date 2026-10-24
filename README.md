
<!-- README.md is generated from README.Rmd. Please edit that file -->

# L1000PAIdata

`L1000PAIdata` supplies the L1000 perturbation signature libraries used
by [`L1000PAI`](https://github.com/yilin1107/L1000PAI). It contains no
signature data. Instead it downloads each library from its public
source, converts it to the `L1000PAI` file format, and keeps it only if
its content fingerprint matches the reference release used for the
L1000PAI analyses (`legacy-local-2026-08-08`).

## Installation

``` r
# install.packages("remotes")
remotes::install_github("yilin1107/L1000PAIdata")
```

## Getting the libraries

``` r
library(L1000PAIdata)

# The two libraries used for paired activity inference (about 32 MB):
download_l1000pai_data(c("crispr", "chem"))

# Every downloadable library:
download_l1000pai_data("all")

list_l1000pai_data_files()
verify_l1000pai_data_files()
```

Files are cached in `l1000pai_data_cache_dir()`; set the environment
variable `L1000PAIDATA_CACHE` to use another directory.

Each `get_l1000pai_data_path()` call rechecks the requested library
against its reference content fingerprint. `list_l1000pai_data_files()`
also checks every present library by default. Corrupted or modified
files are rejected, not used for analysis. Downloads are staged before
replacing cached files; interrupted downloads do not replace an earlier
complete raw file. If a downloaded library fails its content check,
retry with `overwrite = TRUE` to refresh the raw cache. A persistent
mismatch indicates changed or otherwise non-reference content; it must
not be bypassed.

Downloads negotiate the normal HTTPS protocol first. If an HTTP/2 stream
or framing failure occurs, the remaining attempts use a fresh HTTP/1.1
connection. Transient connection failures and HTTP 408, 429 or 5xx
responses have at most three attempts per upstream file, with short
bounded waits. A `Retry-After` longer than 30 seconds or expressed as an
HTTP date stops and asks the user to retry later. TLS certificate
failures, other HTTP errors and fingerprint mismatches are not retried.
No transport fallback disables certificate verification, changes the
source, or accepts an unverified library. The `timeout` argument applies
to each attempt, not to the entire set of libraries.

| Library | Source (Enrichr gene-set library) | Signatures |
|----|----|----|
| `crispr` | `LINCS_L1000_CRISPR_KO_Consensus_Sigs` | 10,424 (5,212 genes × Up/Down) |
| `chem` | `LINCS_L1000_Chem_Pert_Consensus_Sigs` | 10,850 (5,425 compounds × Up/Down) |
| `kinase_gpcr_up`, `kinase_gpcr_down` | `L1000_Kinase_and_GPCR_Perturbations_up` / `_down` | 3,644 each |
| `kinase_gpcr` | both of the above, concatenated | 7,288 |

The conversion only renames signatures (`" Up"`/`" Down"` become
`" up"`/`" dn"`; kinase/GPCR names become `"<gene>(<cell>) up"`). It is
documented in `?download_l1000pai_data`. The content fingerprint
(`?l1000pai_content_sha256`) ignores gene order within a signature,
which the upstream service does not keep fixed; analyses run on
downloaded and reference files give identical results.

The `ligand`, `oe` and `single_drug` libraries have no confirmed
upstream source and are not downloadable. A verified local copy can be
added with `register_l1000pai_data_file()`.

Thus five library identifiers are downloadable (including the combined
kinase/GPCR library and its two arms), and three are local-only. This is
not a claim that all eight libraries can be publicly reproduced from
downloads.

## Data terms and citation

The package is intended for research use, not clinical decision-making.
Libraries are provided by upstream services under their own terms;
review the current [Enrichr resource and
terms](https://maayanlab.cloud/Enrichr/) and the [NIH LINCS program’s
data-sharing information](https://lincsproject.org/) before use. A
public download URL and a matching fingerprint do not establish
permission for commercial use or redistribution. This release provides
no upstream license clearance and does not fill unresolved provenance
fields by inference. When you publish results, cite:

- Subramanian A, et al. A Next Generation Connectivity Map: L1000
  platform and the first 1,000,000 profiles. *Cell* 2017;171:1437–1452.
- Evangelista JE, et al. SigCom LINCS: data and metadata search engine
  for a million gene expression signatures. *Nucleic Acids Res*
  2022;50:W697–W709.
- Xie Z, et al. Gene set knowledge discovery with Enrichr. *Curr Protoc*
  2021;1:e90.

The MIT license of this package covers its code only.
