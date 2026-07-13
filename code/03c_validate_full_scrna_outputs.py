from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path

import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate complete GSE136831 aggregation outputs.")
    parser.add_argument("--analysis-root", required=True, type=Path)
    return parser.parse_args()


def canonical_hash(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    entries = 0
    with gzip.open(path, "rt") as handle:
        for line in handle:
            row, cell, count = (int(value) for value in line.split())
            digest.update(f"{row}\t{cell}\t{count}\n".encode("ascii"))
            entries += 1
    return digest.hexdigest(), entries


def main() -> None:
    args = parse_args()
    analysis_root = args.analysis_root.resolve()
    output_root = analysis_root / "results" / "lung_scrna_full"
    reconstructed = output_root / "GSE136831_target_panel_reconstructed_from_full_mtx.tsv.gz"
    expected = json.loads(
        (analysis_root / "reference" / "GSE136831_target_validation.json").read_text(encoding="utf-8")
    )
    reconstructed_hash, reconstructed_entries = canonical_hash(reconstructed)

    samples = pd.read_csv(output_root / "GSE136831_full_pseudobulk_sample_manifest.tsv", sep="\t")
    totals = pd.read_csv(output_root / "GSE136831_full_pseudobulk_counts.sample_totals.tsv", sep="\t")
    check = samples.merge(totals, on="sample_index", validate="one_to_one")
    check["delta"] = check["raw_matrix_total_umi"] - check["metadata_total_umi"]
    summary = {
        "expected_canonical_sha256": expected["canonical_sha256"],
        "reconstructed_canonical_sha256": reconstructed_hash,
        "expected_entries": expected["entries"],
        "reconstructed_entries": reconstructed_entries,
        "exact_target_match": expected["canonical_sha256"] == reconstructed_hash
        and expected["entries"] == reconstructed_entries,
        "sample_total_umi_exact_matches": int(check["delta"].eq(0).sum()),
        "sample_total_umi_samples": int(len(check)),
        "max_abs_total_umi_delta": int(check["delta"].abs().max()),
    }
    if not summary["exact_target_match"] or summary["max_abs_total_umi_delta"] != 0:
        raise ValueError(f"Full source validation failed: {summary}")
    (output_root / "GSE136831_full_source_validation.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    check[[
        "sample_index", "sample_id", "metadata_total_umi", "raw_matrix_total_umi", "delta"
    ]].to_csv(output_root / "GSE136831_sample_total_umi_validation.csv", index=False)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
