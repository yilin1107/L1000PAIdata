"""Generate the locked manifest for the current local extdata snapshot."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
from collections import Counter
from pathlib import Path


SCHEMA_VERSION = "1.0.0"
DATA_RELEASE_ID = "legacy-local-2026-08-08"

ARTIFACTS = [
    ("kinase_gpcr", "L1000_Kinase_and_GPCR_Consensus_Sigs.txt", "distribution_candidate"),
    ("kinase_gpcr_down", "L1000_Kinase_and_GPCR_Perturbations_down.txt", "distribution_candidate"),
    ("kinase_gpcr_up", "L1000_Kinase_and_GPCR_Perturbations_up.txt", "distribution_candidate"),
    ("ligand", "L1000_Ligand_Consensus_Sigs.gmt", "distribution_candidate"),
    ("oe", "L1000_OverExpression_Consensus_Sigs.gmt", "distribution_candidate"),
    ("crispr", "LINCS_L1000_CRISPR_KO_Consensus_Sigs.txt", "distribution_candidate"),
    ("chem", "LINCS_L1000_Chem_Pert_Consensus_Sigs.txt", "distribution_candidate"),
    ("ligand_all_legacy", "LINCS_L1000_Ligand_Perturbations_All.txt", "orphan_legacy"),
    ("single_drug", "single_drug_perturbations_v1_0.gmt", "distribution_candidate"),
]

KNOWN_ISSUES = {
    "ligand": "duplicate_term_names;context_metadata_not_preserved",
    "oe": "duplicate_term_names;context_metadata_not_preserved",
    "single_drug": "duplicate_term_names;zero_gene_row;species_unverified",
    "ligand_all_legacy": "direction_not_encoded;not_exposed_by_provider_api",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inspect_gmt(path: Path) -> dict[str, int]:
    terms: Counter[str] = Counter()
    genes: set[str] = set()
    line_count = 0
    nonempty_line_count = 0
    empty_signature_count = 0
    max_genes_per_row = 0

    with path.open("r", encoding="utf-8", errors="replace", newline="") as handle:
        for raw_line in handle:
            line_count += 1
            line = raw_line.rstrip("\r\n")
            if not line:
                continue
            nonempty_line_count += 1
            fields = line.split("\t")
            term = fields[0].strip() if fields else ""
            if term:
                terms[term] += 1
            row_genes = [gene.strip() for gene in fields[2:] if gene.strip()]
            if not row_genes:
                empty_signature_count += 1
            genes.update(row_genes)
            max_genes_per_row = max(max_genes_per_row, len(row_genes))

    return {
        "line_count": line_count,
        "nonempty_line_count": nonempty_line_count,
        "unique_term_count": len(terms),
        "duplicated_term_count": sum(count > 1 for count in terms.values()),
        "unique_gene_count": len(genes),
        "empty_signature_count": empty_signature_count,
        "max_genes_per_row": max_genes_per_row,
    }


def write_atomic_csv(path: Path, rows: list[dict]) -> None:
    fields = list(rows[0])
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--extdata",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "extdata",
    )
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    extdata = args.extdata.resolve(strict=True)
    output = args.output or extdata / "library_manifest.csv"

    consensus = extdata / "L1000_Kinase_and_GPCR_Consensus_Sigs.txt"
    up = extdata / "L1000_Kinase_and_GPCR_Perturbations_up.txt"
    down = extdata / "L1000_Kinase_and_GPCR_Perturbations_down.txt"
    verified_concat = consensus.read_bytes() == up.read_bytes() + down.read_bytes()

    rows: list[dict] = []
    for library_id, filename, role in ARTIFACTS:
        path = extdata / filename
        if not path.is_file():
            raise FileNotFoundError(path)
        statistics = inspect_gmt(path)
        lineage_status = "unresolved"
        lineage_note = ""
        if library_id == "kinase_gpcr" and verified_concat:
            lineage_status = "verified_concatenation"
            lineage_note = "byte-for-byte concatenation of kinase_gpcr_up then kinase_gpcr_down"

        rows.append(
            {
                "manifest_schema_version": SCHEMA_VERSION,
                "data_release_id": DATA_RELEASE_ID,
                "library_id": library_id,
                "filename": filename,
                "format": "gmt_like_tsv",
                "artifact_role": role,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                **statistics,
                "source_resource": "",
                "source_accession": "",
                "source_url": "",
                "source_version": "",
                "access_date": "",
                "original_filename": "",
                "organism_taxid": "",
                "gene_id_namespace": "",
                "processing_script": "",
                "upstream_license": "",
                "provenance_status": "unresolved",
                "redistribution_status": "blocked_pending_review",
                "lineage_status": lineage_status,
                "known_issues": KNOWN_ISSUES.get(library_id, "metadata_and_license_unresolved"),
                "notes": lineage_note,
            }
        )

    write_atomic_csv(output, rows)
    print(f"Wrote {len(rows)} artifact records to {output}")


if __name__ == "__main__":
    main()
