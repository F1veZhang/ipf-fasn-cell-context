from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


FINE_CELLTYPE_ORDER = [
    "AT2", "AT1", "Aberrant basaloid", "Basal", "Club", "Ciliated", "Goblet",
    "Ionocyte", "PNEC", "Mesothelial", "Fibroblast", "Myofibroblast", "Pericyte",
    "Smooth muscle", "Alveolar macrophage", "Non-alveolar macrophage", "Monocyte",
    "Endothelial", "T/NK", "B/plasma",
]


def fine_celltype(identity: str, category: str) -> str | None:
    direct = {
        "ATII": "AT2", "ATI": "AT1", "Aberrant_Basaloid": "Aberrant basaloid",
        "Basal": "Basal", "Club": "Club", "Ciliated": "Ciliated", "Goblet": "Goblet",
        "Ionocyte": "Ionocyte", "PNEC": "PNEC", "Mesothelial": "Mesothelial",
        "Fibroblast": "Fibroblast", "Myofibroblast": "Myofibroblast",
        "Pericyte": "Pericyte", "SMC": "Smooth muscle",
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize FASN absolute expression after full-matrix target reconstruction."
    )
    parser.add_argument("--raw-data-root", required=True, type=Path)
    parser.add_argument("--analysis-root", required=True, type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    raw_root = args.raw_data_root.resolve()
    analysis_root = args.analysis_root.resolve()
    data_root = raw_root / "GSE136831"
    output_root = analysis_root / "results" / "lung_scrna_full"

    metadata = pd.read_csv(
        data_root / "GSE136831_AllCells.Samples.CellType.MetadataTable.txt.gz", sep="\t"
    )
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

    genes = pd.read_csv(output_root / "GSE136831_gene_manifest.tsv", sep="\t")
    fasn_row = int(genes.loc[genes["symbol"].eq("FASN"), "row_index"].iloc[0])
    target_counts = pd.read_csv(
        output_root / "GSE136831_target_panel_reconstructed_from_full_mtx.tsv.gz",
        sep=r"\s+", header=None, names=["row_index", "cell_idx", "count"],
        dtype=np.int32,
    )
    fasn_counts = target_counts.loc[target_counts["row_index"].eq(fasn_row)].merge(
        selected[
            ["cell_idx", "sample_id", "Subject_Identity", "Disease_Identity", "fine_celltype", "nUMI"]
        ],
        on="cell_idx", how="inner", validate="one_to_one",
    )
    fasn_counts["FASN_positive_cell_CP10K"] = 1e4 * fasn_counts["count"] / fasn_counts["nUMI"]

    sample_manifest = pd.read_csv(
        output_root / "GSE136831_full_pseudobulk_sample_manifest.tsv", sep="\t"
    )
    positive_by_sample = (
        fasn_counts.groupby("sample_id", observed=True, as_index=False)
        .agg(
            FASN_raw_count=("count", "sum"),
            FASN_expressing_cells=("cell_idx", "nunique"),
            FASN_positive_cell_mean_raw_count=("count", "mean"),
            FASN_positive_cell_median_raw_count=("count", "median"),
            FASN_positive_cell_mean_CP10K=("FASN_positive_cell_CP10K", "mean"),
            FASN_positive_cell_median_CP10K=("FASN_positive_cell_CP10K", "median"),
        )
    )
    donor = sample_manifest.merge(positive_by_sample, on="sample_id", how="left", validate="one_to_one")
    for column in ["FASN_raw_count", "FASN_expressing_cells"]:
        donor[column] = donor[column].fillna(0).astype(int)
    donor["FASN_detection_rate"] = donor["FASN_expressing_cells"] / donor["n_cells"]
    donor["FASN_CP10K"] = 1e4 * donor["FASN_raw_count"] / donor["metadata_total_umi"]
    donor.to_csv(output_root / "GSE136831_FASN_donor_detection_summary.csv", index=False)

    celltype_totals = (
        selected.groupby("fine_celltype", observed=True, as_index=False)
        .agg(n_cells=("cell_idx", "size"), total_umi=("nUMI", "sum"))
    )
    localization = (
        fasn_counts.groupby("fine_celltype", observed=True, as_index=False)
        .agg(FASN_sum_count=("count", "sum"), FASN_expressing_cells=("cell_idx", "nunique"))
    )
    localization = (
        pd.DataFrame({"fine_celltype": FINE_CELLTYPE_ORDER})
        .merge(celltype_totals, on="fine_celltype", how="left")
        .merge(localization, on="fine_celltype", how="left")
        .fillna(0)
    )
    localization["FASN_pct_expressing"] = (
        100 * localization["FASN_expressing_cells"] / localization["n_cells"]
    )
    localization["FASN_average_CP10K"] = 1e4 * localization["FASN_sum_count"] / localization["total_umi"]
    localization.to_csv(output_root / "GSE136831_FASN_fine_celltype_localization.csv", index=False)

    disease_totals = (
        selected.groupby(["fine_celltype", "Disease_Identity"], observed=True, as_index=False)
        .agg(n_cells=("cell_idx", "size"), total_umi=("nUMI", "sum"), n_donors=("Subject_Identity", "nunique"))
    )
    disease_fasn = (
        fasn_counts.groupby(["fine_celltype", "Disease_Identity"], observed=True, as_index=False)
        .agg(
            FASN_raw_count=("count", "sum"),
            FASN_expressing_cells=("cell_idx", "nunique"),
            FASN_positive_cell_mean_raw_count=("count", "mean"),
            FASN_positive_cell_median_raw_count=("count", "median"),
            FASN_positive_cell_mean_CP10K=("FASN_positive_cell_CP10K", "mean"),
            FASN_positive_cell_median_CP10K=("FASN_positive_cell_CP10K", "median"),
        )
    )
    grid = pd.MultiIndex.from_product(
        [FINE_CELLTYPE_ORDER, ["Control", "IPF"]], names=["fine_celltype", "Disease_Identity"]
    ).to_frame(index=False)
    disease = grid.merge(disease_totals, on=["fine_celltype", "Disease_Identity"], how="left").merge(
        disease_fasn, on=["fine_celltype", "Disease_Identity"], how="left"
    ).fillna(0)
    disease["FASN_mean_raw_count_per_cell"] = disease["FASN_raw_count"] / disease["n_cells"]
    disease["FASN_median_raw_count_per_cell"] = 0.0
    disease["FASN_detection_rate"] = disease["FASN_expressing_cells"] / disease["n_cells"]
    disease["FASN_CP10K"] = 1e4 * disease["FASN_raw_count"] / disease["total_umi"]
    disease.to_csv(output_root / "GSE136831_FASN_disease_specific_absolute_expression.csv", index=False)

    primary = donor.loc[donor["n_cells"].ge(20)].copy()
    donor_summary = (
        primary.groupby(["fine_celltype", "Disease_Identity"], observed=True, as_index=False)
        .agg(
            n_donors=("Subject_Identity", "nunique"),
            median_FASN_CP10K=("FASN_CP10K", "median"),
            Q1_FASN_CP10K=("FASN_CP10K", lambda x: x.quantile(0.25)),
            Q3_FASN_CP10K=("FASN_CP10K", lambda x: x.quantile(0.75)),
            median_FASN_detection_rate=("FASN_detection_rate", "median"),
            Q1_FASN_detection_rate=("FASN_detection_rate", lambda x: x.quantile(0.25)),
            Q3_FASN_detection_rate=("FASN_detection_rate", lambda x: x.quantile(0.75)),
        )
    )
    donor_summary.to_csv(
        output_root / "GSE136831_FASN_donor_level_absolute_summary_primary20.csv", index=False
    )
    print(f"Wrote donor and disease absolute-expression summaries for {len(donor)} samples")


if __name__ == "__main__":
    main()
