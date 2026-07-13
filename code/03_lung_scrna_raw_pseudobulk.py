from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path

import numpy as np
import pandas as pd


parser = argparse.ArgumentParser(description="Prepare the targeted GSE136831 sensitivity inputs.")
parser.add_argument("--raw-data-root", required=True, type=Path)
parser.add_argument("--analysis-root", required=True, type=Path)
args = parser.parse_args()
RAW_DATA = args.raw_data_root.resolve()
ANALYSIS = args.analysis_root.resolve()
DATA = RAW_DATA / "GSE136831"
OUT = ANALYSIS / "results" / "lung_scrna"
OUT.mkdir(parents=True, exist_ok=True)

GENE_FILE = DATA / "GSE136831_AllCells.GeneIDs.txt.gz"
BARCODE_FILE = DATA / "GSE136831_AllCells.cellBarcodes.txt.gz"
META_FILE = DATA / "GSE136831_AllCells.Samples.CellType.MetadataTable.txt.gz"
MATRIX_FILE = DATA / "GSE136831_RawCounts_Sparse.mtx.gz"
TARGET_FILE = ANALYSIS / "results" / "lung_scrna_full" / "GSE136831_target_panel_reconstructed_from_full_mtx.tsv.gz"

CELLTYPE_ORDER = [
    "AT2",
    "AT1",
    "Aberrant basaloid",
    "Other epithelial",
    "Fibroblast",
    "Myofibroblast",
    "Macrophage",
    "Monocyte",
    "Endothelial",
    "T/NK",
    "B/plasma",
]

CANDIDATES = ["FASN", "ACACB", "LPCAT2", "GLO1", "PGM2L1", "GGCX", "INPP5D", "CA4"]

MARKERS = {
    "AT2": ["SFTPC", "SFTPA1", "SFTPA2", "ABCA3", "SLC34A2"],
    "AT1": ["AGER", "PDPN", "CAV1", "HOPX", "RTKN2"],
    "Aberrant basaloid": ["KRT5", "KRT17", "KRT8", "KRT19", "TP63"],
    "Fibroblast": ["COL1A1", "COL1A2", "DCN", "LUM"],
    "Myofibroblast": ["ACTA2", "TAGLN", "MYH11", "COL3A1", "POSTN"],
    "Macrophage": ["MARCO", "LYZ", "C1QA", "SPP1", "MSR1"],
    "Monocyte": ["FCN1", "LST1", "S100A8", "S100A9", "VCAN"],
    "Endothelial": ["PECAM1", "VWF", "KDR", "CLDN5"],
    "T/NK": ["CD3D", "CD3E", "NKG7", "GNLY", "TRAC"],
    "B/plasma": ["MS4A1", "CD79A", "CD79B"],
}


def major_celltype(row: pd.Series) -> str:
    ident = str(row["Manuscript_Identity"])
    category = str(row["CellType_Category"])
    if ident == "ATII":
        return "AT2"
    if ident == "ATI":
        return "AT1"
    if ident == "Aberrant_Basaloid":
        return "Aberrant basaloid"
    if ident in {"Ciliated", "Club", "Goblet", "Basal", "PNEC", "Ionocyte"}:
        return "Other epithelial"
    if ident == "Fibroblast":
        return "Fibroblast"
    if ident == "Myofibroblast":
        return "Myofibroblast"
    if ident in {"Macrophage", "Macrophage_Alveolar"}:
        return "Macrophage"
    if ident in {"cMonocyte", "ncMonocyte"}:
        return "Monocyte"
    if category == "Endothelial" or ident.startswith("VE_") or ident == "Lymphatic":
        return "Endothelial"
    if ident in {"T", "T_Cytotoxic", "T_Regulatory", "NK", "ILC_A", "ILC_B"}:
        return "T/NK"
    if ident in {"B", "B_Plasma"}:
        return "B/plasma"
    return "Other"


def validate_target_subset(
    target_counts: pd.DataFrame, target_rows: set[int], verify_cells: int = 5000
) -> dict[str, int | bool]:
    raw_entries: dict[tuple[int, int], int] = {}
    dimensions: tuple[int, int, int] | None = None
    previous_col = 0
    with gzip.open(MATRIX_FILE, "rt") as handle:
        for line in handle:
            if line.startswith("%"):
                continue
            if dimensions is None:
                parts = line.split()
                dimensions = (int(parts[0]), int(parts[1]), int(parts[2]))
                continue
            row_s, col_s, count_s = line.split()
            row, col, count = int(row_s), int(col_s), int(count_s)
            if col < previous_col:
                raise ValueError("Matrix Market coordinates are not sorted by cell column")
            previous_col = col
            if col > verify_cells:
                break
            if row in target_rows:
                raw_entries[(row, col)] = count

    target_head = target_counts.loc[target_counts["cell_idx"] <= verify_cells]
    target_entries = {
        (int(row), int(col)): int(count)
        for row, col, count in target_head[["row", "cell_idx", "count"]].itertuples(index=False)
    }
    exact = raw_entries == target_entries
    if not exact:
        raw_keys = set(raw_entries)
        target_keys = set(target_entries)
        missing = len(raw_keys - target_keys)
        extra = len(target_keys - raw_keys)
        mismatched = sum(
            raw_entries[key] != target_entries[key] for key in raw_keys & target_keys
        )
        raise ValueError(
            f"Target subset failed raw-matrix verification: missing={missing}, "
            f"extra={extra}, mismatched={mismatched}"
        )
    assert dimensions is not None
    return {
        "verified_cells": verify_cells,
        "verified_target_entries": len(raw_entries),
        "exact_match": exact,
        "matrix_rows": dimensions[0],
        "matrix_columns": dimensions[1],
        "matrix_nonzero_entries": dimensions[2],
    }


def main() -> None:
    genes = pd.read_csv(GENE_FILE, sep="\t")
    genes.columns = ["ensembl", "symbol"]
    genes["row"] = np.arange(1, len(genes) + 1)
    genes["symbol"] = genes["symbol"].astype(str).str.upper()

    barcodes = pd.read_csv(BARCODE_FILE, header=None, names=["barcode"])
    meta = pd.read_csv(META_FILE, sep="\t")
    if not meta["CellBarcode_Identity"].reset_index(drop=True).equals(
        barcodes["barcode"].reset_index(drop=True)
    ):
        raise ValueError("Cell metadata and barcode order do not match")
    meta = meta.reset_index(drop=True)
    meta["cell_idx"] = np.arange(1, len(meta) + 1)
    meta["major_celltype"] = meta.apply(major_celltype, axis=1)

    target_counts = pd.read_csv(
        TARGET_FILE,
        sep=r"\s+",
        header=None,
        names=["row", "cell_idx", "count"],
        engine="c",
        dtype={"row": np.int32, "cell_idx": np.int32, "count": np.int32},
    )
    target_rows = set(target_counts["row"].unique().tolist())
    validation = validate_target_subset(target_counts, target_rows, verify_cells=5000)

    row_manifest = genes.loc[genes["row"].isin(target_rows), ["row", "ensembl", "symbol"]].copy()
    row_manifest.to_csv(OUT / "GSE136831_raw_target_gene_manifest.csv", index=False)
    row_to_symbol = row_manifest.set_index("row")["symbol"].to_dict()
    target_counts["gene"] = target_counts["row"].map(row_to_symbol)
    target_counts = target_counts.dropna(subset=["gene"])

    meta = meta.loc[
        meta["Disease_Identity"].isin(["Control", "IPF"])
        & meta["major_celltype"].isin(CELLTYPE_ORDER)
    ].copy()
    meta["sample_id"] = meta["Subject_Identity"].astype(str) + "__" + meta["major_celltype"]

    sample_meta = (
        meta.groupby(
            ["sample_id", "Subject_Identity", "Disease_Identity", "major_celltype"],
            observed=True,
            as_index=False,
        )
        .agg(n_cells=("cell_idx", "size"), total_umi=("nUMI", "sum"))
    )
    sample_meta.to_csv(OUT / "GSE136831_donor_celltype_sample_metadata.csv", index=False)

    counts = target_counts.merge(
        meta[["cell_idx", "sample_id"]], on="cell_idx", how="inner", validate="many_to_one"
    )
    pseudobulk = (
        counts.groupby(["sample_id", "gene"], observed=True, as_index=False)
        .agg(raw_count=("count", "sum"))
        .merge(sample_meta, on="sample_id", how="left", validate="many_to_one")
    )
    pseudobulk.to_csv(OUT / "GSE136831_raw_target_gene_pseudobulk_long.csv", index=False)

    fasn = sample_meta.merge(
        pseudobulk.loc[pseudobulk["gene"] == "FASN", ["sample_id", "raw_count"]],
        on="sample_id",
        how="left",
    )
    fasn["raw_count"] = fasn["raw_count"].fillna(0).astype(int)
    fasn["CPM"] = 1e6 * (fasn["raw_count"] + 0.5) / (fasn["total_umi"] + 1.0)
    fasn["log2_CPM"] = np.log2(fasn["CPM"])
    fasn.to_csv(OUT / "GSE136831_FASN_raw_donor_pseudobulk.csv", index=False)

    celltype_totals = (
        meta.groupby("major_celltype", observed=True, as_index=False)
        .agg(n_cells=("cell_idx", "size"), total_umi=("nUMI", "sum"))
    )
    candidate_counts = (
        counts.loc[counts["gene"].isin(CANDIDATES)]
        .merge(meta[["cell_idx", "major_celltype"]], on="cell_idx", how="left")
        .groupby(["major_celltype", "gene"], observed=True, as_index=False)
        .agg(sum_count=("count", "sum"), expressing_cells=("cell_idx", "nunique"))
    )
    candidate_grid = pd.MultiIndex.from_product(
        [CELLTYPE_ORDER, CANDIDATES], names=["major_celltype", "gene"]
    ).to_frame(index=False)
    candidate_dot = (
        candidate_grid.merge(candidate_counts, on=["major_celltype", "gene"], how="left")
        .merge(celltype_totals, on="major_celltype", how="left")
    )
    candidate_dot[["sum_count", "expressing_cells"]] = candidate_dot[
        ["sum_count", "expressing_cells"]
    ].fillna(0)
    candidate_dot["pct_expr"] = 100 * candidate_dot["expressing_cells"] / candidate_dot["n_cells"]
    candidate_dot["avg_cp10k"] = 1e4 * candidate_dot["sum_count"] / candidate_dot["total_umi"]
    candidate_dot["avg_log1p_cp10k"] = np.log1p(candidate_dot["avg_cp10k"])
    candidate_dot.to_csv(OUT / "GSE136831_candidate_localization_from_raw_counts.csv", index=False)

    marker_long = pd.DataFrame(
        [(celltype, gene) for celltype, marker_genes in MARKERS.items() for gene in marker_genes],
        columns=["marker_celltype", "gene"],
    )
    marker_counts = (
        counts.loc[counts["gene"].isin(marker_long["gene"])]
        .merge(meta[["cell_idx", "major_celltype"]], on="cell_idx", how="left")
        .groupby(["major_celltype", "gene"], observed=True, as_index=False)
        .agg(sum_count=("count", "sum"), expressing_cells=("cell_idx", "nunique"))
        .merge(celltype_totals, on="major_celltype", how="left")
    )
    marker_counts["avg_cp10k"] = 1e4 * marker_counts["sum_count"] / marker_counts["total_umi"]
    marker_counts["pct_expr"] = 100 * marker_counts["expressing_cells"] / marker_counts["n_cells"]
    marker_counts = marker_counts.merge(marker_long, on="gene", how="left")
    marker_counts.to_csv(OUT / "GSE136831_marker_reference_from_raw_counts.csv", index=False)

    cell_counts = (
        meta.groupby(["Disease_Identity", "major_celltype"], observed=True)
        .size()
        .reset_index(name="n_cells")
    )
    cell_counts.to_csv(OUT / "GSE136831_cell_counts_after_disease_celltype_filter.csv", index=False)

    validation.update(
        {
            "metadata_cells_total": int(len(barcodes)),
            "analysis_cells_control_or_ipf": int(len(meta)),
            "control_donors": int(meta.loc[meta["Disease_Identity"] == "Control", "Subject_Identity"].nunique()),
            "ipf_donors": int(meta.loc[meta["Disease_Identity"] == "IPF", "Subject_Identity"].nunique()),
            "target_rows": int(len(target_rows)),
            "target_symbols": int(row_manifest["symbol"].nunique()),
        }
    )
    (OUT / "GSE136831_raw_subset_validation.json").write_text(
        json.dumps(validation, indent=2), encoding="utf-8"
    )
    print(json.dumps(validation, indent=2))


if __name__ == "__main__":
    main()
