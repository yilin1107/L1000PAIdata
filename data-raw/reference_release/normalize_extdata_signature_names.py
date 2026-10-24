#!/usr/bin/env python3
"""Normalize bundled extdata signature names and build merged consensus files."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


CHEM_CRISPR_FILES = {
    "LINCS_L1000_Chem_Pert_Consensus_Sigs.txt",
    "LINCS_L1000_CRISPR_KO_Consensus_Sigs.txt",
}

KINASE_GPCR_UP = "L1000_Kinase_and_GPCR_Perturbations_up.txt"
KINASE_GPCR_DOWN = "L1000_Kinase_and_GPCR_Perturbations_down.txt"
KINASE_GPCR_CONSENSUS = "L1000_Kinase_and_GPCR_Consensus_Sigs.txt"


def rewrite_term(term: str, file_name: str) -> str:
    if file_name == "single_drug_perturbations_v1_0.gmt":
        term = re.sub(r"(?i)-down$", " dn", term)
        term = re.sub(r"(?i)-dn$", " dn", term)
        term = re.sub(r"(?i)-up$", " up", term)
        return term

    if file_name in CHEM_CRISPR_FILES:
        term = re.sub(r"(?i)\s+down$", " dn", term)
        term = re.sub(r"(?i)\s+up$", " up", term)
        return term

    if file_name == "LINCS_L1000_Ligand_Perturbations_All.txt":
        ligand, cellline = term.rsplit("-", 1)
        return f"{ligand}({cellline})"

    if file_name in {KINASE_GPCR_UP, KINASE_GPCR_DOWN}:
        match = re.match(r"^(?P<gene>.+?)\s+knockdown\s+\S+\s+(?P<cell>\S+)$", term, re.IGNORECASE)
        if not match:
            raise ValueError(f"Unexpected kinase/gpcr term format: {term}")
        direction = "up" if file_name == KINASE_GPCR_UP else "dn"
        return f"{match.group('gene')}({match.group('cell')}) {direction}"

    return term


def normalize_file(path: Path, write: bool) -> list[str]:
    changed = 0
    output_lines: list[str] = []

    with path.open("r", encoding="utf-8", errors="replace", newline="") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\r\n")
            if not line:
                output_lines.append(raw_line)
                continue

            fields = line.split("\t")
            original = fields[0]
            normalized = rewrite_term(original, path.name)
            if normalized != original:
                changed += 1
            fields[0] = normalized
            output_lines.append("\t".join(fields) + "\n")

    if write and changed:
        with path.open("w", encoding="utf-8", newline="") as handle:
            handle.writelines(output_lines)

    print(f"{'rewrote' if write else 'would rewrite'}\t{path.name}\tchanged={changed}")
    return output_lines


def build_kinase_gpcr_consensus(extdata_dir: Path, write: bool) -> None:
    up_path = extdata_dir / KINASE_GPCR_UP
    down_path = extdata_dir / KINASE_GPCR_DOWN
    consensus_path = extdata_dir / KINASE_GPCR_CONSENSUS

    up_lines = up_path.read_text(encoding="utf-8", errors="replace").splitlines()
    down_lines = down_path.read_text(encoding="utf-8", errors="replace").splitlines()
    consensus_lines = [f"{line}\n" for line in up_lines + down_lines if line]

    if write:
        with consensus_path.open("w", encoding="utf-8", newline="") as handle:
            handle.writelines(consensus_lines)
        print(f"wrote\t{consensus_path.name}\tlines={len(consensus_lines)}")
    else:
        print(f"would write\t{consensus_path.name}\tlines={len(consensus_lines)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("extdata_dir", type=Path, help="Path to inst/extdata")
    parser.add_argument("--write", action="store_true", help="Rewrite files in place")
    args = parser.parse_args()

    extdata_dir = args.extdata_dir
    files_to_normalize = [
        extdata_dir / "single_drug_perturbations_v1_0.gmt",
        extdata_dir / "LINCS_L1000_Chem_Pert_Consensus_Sigs.txt",
        extdata_dir / "LINCS_L1000_CRISPR_KO_Consensus_Sigs.txt",
        extdata_dir / "LINCS_L1000_Ligand_Perturbations_All.txt",
        extdata_dir / KINASE_GPCR_UP,
        extdata_dir / KINASE_GPCR_DOWN,
    ]

    for path in files_to_normalize:
        if not path.exists():
            raise SystemExit(f"Missing expected file: {path}")
        normalize_file(path, write=args.write)

    build_kinase_gpcr_consensus(extdata_dir, write=args.write)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
