from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd


FINE_CELLTYPE_ORDER = [
    "AT2",
    "AT1",
    "Aberrant basaloid",
    "Basal",
    "Club",
    "Ciliated",
    "Goblet",
    "Ionocyte",
    "PNEC",
    "Mesothelial",
    "Fibroblast",
    "Myofibroblast",
    "Pericyte",
    "Smooth muscle",
    "Alveolar macrophage",
    "Non-alveolar macrophage",
    "Monocyte",
    "Endothelial",
    "T/NK",
    "B/plasma",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare cell and sample maps for full-transcriptome GSE136831 pseudobulk."
    )
    parser.add_argument("--raw-data-root", required=True, type=Path)
    parser.add_argument("--analysis-root", required=True, type=Path)
    parser.add_argument("--target-manifest", type=Path)
    return parser.parse_args()


def fine_celltype(identity: str, category: str) -> str | None:
    direct = {
        "ATII": "AT2",
        "ATI": "AT1",
        "Aberrant_Basaloid": "Aberrant basaloid",
        "Basal": "Basal",
        "Club": "Club",
        "Ciliated": "Ciliated",
        "Goblet": "Goblet",
        "Ionocyte": "Ionocyte",
        "PNEC": "PNEC",
        "Mesothelial": "Mesothelial",
        "Fibroblast": "Fibroblast",
        "Myofibroblast": "Myofibroblast",
        "Pericyte": "Pericyte",
        "SMC": "Smooth muscle",
    }
    if identity in direct:
        return direct[identity]
    if identity == "Macrophage_Alveolar":
        return "Alveolar macrophage"
    if identity == "Macrophage":
        return "Non-alveolar macrophage"
    if identity in {"cMonocyte", "ncMonocyte"}:
        return "Monocyte"
    if category == "Endothelial" or identity.startswith("VE_") or identity == "Lymphatic":
        return "Endothelial"
    if identity in {"T", "T_Cytotoxic", "T_Regulatory", "NK", "ILC_A", "ILC_B"}:
        return "T/NK"
    if identity in {"B", "B_Plasma"}:
        return "B/plasma"
    return None


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    args = parse_args()
    raw_data_root = args.raw_data_root.resolve()
    analysis_root = args.analysis_root.resolve()
    data_root = raw_data_root / "GSE136831"
    target_manifest_path = (
        args.target_manifest.resolve()
        if args.target_manifest
        else analysis_root / "reference" / "GSE136831_target_gene_manifest.csv"
    )
    target_validation_path = analysis_root / "reference" / "GSE136831_target_validation.json"
    output_root = analysis_root / "results" / "lung_scrna_full"
    output_root.mkdir(parents=True, exist_ok=True)

    gene_file = data_root / "GSE136831_AllCells.GeneIDs.txt.gz"
    barcode_file = data_root / "GSE136831_AllCells.cellBarcodes.txt.gz"
    metadata_file = data_root / "GSE136831_AllCells.Samples.CellType.MetadataTable.txt.gz"
    matrix_file = data_root / "GSE136831_RawCounts_Sparse.mtx.gz"

    genes = pd.read_csv(gene_file, sep="\t")
    genes.columns = ["ensembl", "symbol"]
    genes["row_index"] = np.arange(1, len(genes) + 1, dtype=np.int32)
    genes.to_csv(output_root / "GSE136831_gene_manifest.tsv", sep="\t", index=False)

    barcodes = pd.read_csv(barcode_file, header=None, names=["barcode"])
    metadata = pd.read_csv(metadata_file, sep="\t")
    if len(metadata) != len(barcodes):
        raise ValueError("Metadata and barcode files have different cell counts")
    if not metadata["CellBarcode_Identity"].reset_index(drop=True).equals(
        barcodes["barcode"].reset_index(drop=True)
    ):
        raise ValueError("Metadata and barcode order do not match")
    metadata["cell_idx"] = np.arange(1, len(metadata) + 1, dtype=np.int32)

    metadata["fine_celltype"] = [
        fine_celltype(str(identity), str(category))
        for identity, category in zip(
            metadata["Manuscript_Identity"], metadata["CellType_Category"], strict=True
        )
    ]
    eligible = metadata["Disease_Identity"].isin(["Control", "IPF"]) & metadata[
        "fine_celltype"
    ].notna()
    selected = metadata.loc[eligible].copy()
    selected["sample_id"] = (
        selected["Subject_Identity"].astype(str) + "__" + selected["fine_celltype"]
    )

    sample_manifest = (
        selected.groupby(
            ["sample_id", "Subject_Identity", "Disease_Identity", "fine_celltype"],
            observed=True,
            as_index=False,
        )
        .agg(
            n_cells=("CellBarcode_Identity", "size"),
            metadata_total_umi=("nUMI", "sum"),
            n_libraries=("Library_Identity", "nunique"),
            library_ids=("Library_Identity", lambda values: ";".join(sorted(set(map(str, values))))),
        )
    )
    sample_manifest["library_replication"] = np.where(
        sample_manifest["n_libraries"].gt(1), "Multiple libraries", "Single library"
    )
    sample_manifest["fine_celltype"] = pd.Categorical(
        sample_manifest["fine_celltype"], categories=FINE_CELLTYPE_ORDER, ordered=True
    )
    sample_manifest = sample_manifest.sort_values(
        ["fine_celltype", "Disease_Identity", "Subject_Identity"]
    ).reset_index(drop=True)
    sample_manifest["sample_index"] = np.arange(1, len(sample_manifest) + 1, dtype=np.int32)
    sample_manifest["fine_celltype"] = sample_manifest["fine_celltype"].astype(str)
    sample_manifest.to_csv(
        output_root / "GSE136831_full_pseudobulk_sample_manifest.tsv", sep="\t", index=False
    )
    sample_manifest.to_csv(
        output_root / "GSE136831_full_pseudobulk_sample_manifest.csv", index=False
    )

    disease_library = (
        selected.groupby(
            ["Library_Identity", "Subject_Identity", "Disease_Identity"],
            observed=True,
            as_index=False,
        )
        .agg(n_cells=("CellBarcode_Identity", "size"), total_umi=("nUMI", "sum"))
        .sort_values(["Disease_Identity", "Subject_Identity", "Library_Identity"])
    )
    disease_library.to_csv(
        output_root / "GSE136831_disease_by_library_distribution.csv", index=False
    )
    donor_library = (
        selected.groupby(["Subject_Identity", "Disease_Identity"], observed=True, as_index=False)
        .agg(
            n_cells=("CellBarcode_Identity", "size"),
            total_umi=("nUMI", "sum"),
            n_libraries=("Library_Identity", "nunique"),
            library_ids=("Library_Identity", lambda values: ";".join(sorted(set(map(str, values))))),
        )
        .sort_values(["Disease_Identity", "Subject_Identity"])
    )
    donor_library.to_csv(
        output_root / "GSE136831_donor_library_manifest.csv", index=False
    )

    sample_index = sample_manifest.set_index("sample_id")["sample_index"].to_dict()
    cell_map = np.zeros(len(metadata), dtype=np.int32)
    cell_map[np.flatnonzero(eligible.to_numpy())] = selected["sample_id"].map(sample_index).to_numpy(
        dtype=np.int32
    )
    cell_map_path = output_root / "GSE136831_cell_to_sample_index.txt"
    np.savetxt(cell_map_path, cell_map, fmt="%d")

    target_manifest = pd.read_csv(target_manifest_path)
    target_rows = target_manifest["row"].astype(np.int32).drop_duplicates().sort_values()
    expected_symbols = target_manifest.set_index("row")["symbol"]
    observed_symbols = genes.set_index("row_index").loc[target_rows, "symbol"]
    if not observed_symbols.astype(str).equals(expected_symbols.loc[target_rows].astype(str)):
        raise ValueError("Target-gene manifest does not match the raw GSE136831 gene order")
    target_rows.to_csv(
        output_root / "GSE136831_target_row_indices.txt", index=False, header=False
    )
    target_validation = json.loads(target_validation_path.read_text(encoding="utf-8"))

    summary = {
        "matrix_file": "GSE136831/GSE136831_RawCounts_Sparse.mtx.gz",
        "matrix_file_sha256": file_sha256(matrix_file),
        "target_manifest": "reference/GSE136831_target_gene_manifest.csv",
        "expected_target_canonical_sha256": target_validation["canonical_sha256"],
        "expected_target_entries": target_validation["entries"],
        "metadata_cells": int(len(metadata)),
        "included_cells": int(eligible.sum()),
        "ignored_cells": int((~eligible).sum()),
        "pseudobulk_samples": int(len(sample_manifest)),
        "genes": int(len(genes)),
        "target_rows": int(len(target_rows)),
        "fine_celltypes": FINE_CELLTYPE_ORDER,
    }
    (output_root / "GSE136831_full_pseudobulk_preparation.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
