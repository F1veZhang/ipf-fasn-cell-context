import fs from "node:fs/promises";
import zlib from "node:zlib";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const root = process.argv[2];
if (!root) throw new Error("Usage: node build_supplement_v1_3_1.mjs <analysis-root>");
const output = `${root}/Supplement_v1.3.1_20260712.xlsx`;
const previewDir = `${root}/tmp/xlsx_previews_v1.3.1`;
await fs.rm(previewDir, { recursive: true, force: true });
await fs.mkdir(previewDir, { recursive: true });

const workbook = Workbook.create();

const readme = workbook.worksheets.add("README");
readme.getRange("A1:B14").values = [
  ["Item", "Description"],
  ["Purpose", "Source data, model outputs, and reproducibility record for the v1.3.1 source-level IPF transcriptomic release."],
  ["Version", "v1.3.1_20260712"],
  ["Focal rule", "Six genes met AT2 FDR significance, dual fatty-acid leading-edge membership, and three-cohort measurement. FASN had the smallest nominal whole-lung meta-analysis P and was selected for deepest contextual analysis."],
  ["Whole-lung family", "13,632 genes with estimable Hedges' g in all three cohorts; Hartung-Knapp FDR was calculated across this complete intersection."],
  ["Raw single-cell input", "The complete 45,947 x 312,928 UMI matrix was streamed and aggregated to 964 donor-cell-type samples after separating alveolar and non-alveolar macrophages."],
  ["Full source validation", "All 2,363,040 target-panel coordinates were reconstructed from the complete matrix; canonical SHA-256 hashes matched exactly."],
  ["Pseudobulk", "Dispersion was estimated from the full transcriptome. The primary threshold required at least 20 cells per donor-cell type."],
  ["Library audit", "Library_Identity was donor-specific and disease-nested, so source-library and disease effects were not separately estimable. Multiple-library donor status is a technical-replication sensitivity only."],
  ["Low abundance", "Donor-level CP10K, detection prevalence, quasibinomial models, empirical-logit sensitivity, and positive-cell normalized abundance are reported for FASN."],
  ["Offset correction", "The targeted 62-gene sensitivity retains the external full-library total UMI after subsetting; it is not the primary cell-level analysis."],
  ["Composition", "Marker-score and NNLS outputs are reference-dependent sensitivity analyses, not measured cell fractions."],
  ["Interpretation", "Whole-lung FASN directions were concordant but not FDR-supported; full-transcriptome pseudobulk showed a low-abundance negative ciliated effect and a positive alveolar-macrophage prevalence effect within GSE136831."],
  ["Machine readability", "Large result sheets are flat tables; identifiers, thresholds, P values, FDR values, donor counts, and model labels are stored in separate columns."],
];

const meta = workbook.worksheets.add("Dataset_Metadata");
meta.getRange("A1:H6").values = [
  ["Dataset", "Modality", "Source input", "Control donors", "IPF donors", "Cells", "Primary role", "Boundary"],
  ["GSE245965", "Purified AT2 RNA-seq", "Raw counts", 3, 2, null, "AT2 differential expression and pathways", "Five samples"],
  ["GSE150910", "Whole-lung RNA-seq", "Raw counts", 103, 103, null, "Standardized synthesis and composition sensitivity", "Bulk tissue"],
  ["GSE110147", "Whole-lung microarray", "48 raw CEL; RMA", 11, 22, null, "Standardized synthesis and composition sensitivity", "High adjusted-model collinearity"],
  ["GSE24206", "Whole-lung microarray", "23 raw CEL; RMA", 6, 17, null, "Standardized synthesis and composition sensitivity", "Small cohort"],
  ["GSE136831", "Lung scRNA-seq", "Complete raw UMI matrix", 28, 32, 232056, "Full-transcriptome donor pseudobulk", "Donor-specific libraries nested in disease"],
];

const audit = workbook.worksheets.add("Technical_Audit");
audit.getRange("A1:E14").values = [
  ["Layer", "Issue tested", "v1.3.1 method", "Final result", "Primary interpretation"],
  ["AT2 counts", "Threshold and sample sensitivity", "Robust voom plus leave-one-sample-out", "789 up; 795 down; pathways more stable than DEG counts", "Emphasize coordinated programs"],
  ["FASN focal rule", "Rule assumed to identify FASN uniquely", "Complete rule-positive reconstruction", "Six genes met the rule; FASN had the smallest nominal whole-lung P", "Transparent contextual case study"],
  ["AT2 FASN omission", "Single-sample dependence", "Full filter-voom refit after each omission", "Direction negative in all models; FDR 0.0347-0.127", "Direction stable; significance sample-sensitive"],
  ["Whole-lung family", "Restricted 145-gene panel", "13,632-gene three-cohort transcriptome intersection", "0 genes at FDR<0.10; FASN FDR 0.818", "No corrected discovery"],
  ["Targeted offset", "keep.lib.sizes=FALSE reset the external total UMI", "keep.lib.sizes=TRUE plus explicit total-UMI reset", "AT2 Hedges' g and edgeR directions aligned", "Targeted output retained as sensitivity only"],
  ["Full pseudobulk", "62-gene dispersion estimation", "Complete 45,947-gene donor pseudobulk", "34 estimable threshold-by-cell-type comparisons", "Primary cell-level model"],
  ["Epithelial subtype", "Broad other-epithelial category", "Basal, club, ciliated, goblet, AT1, AT2 and other subtypes separated", "Threshold-consistent low-abundance negative ciliated effect", "Subtype-specific signal within one atlas"],
  ["Macrophage subtype", "Aggregate macrophage ambiguity", "Alveolar and non-alveolar compartments separated", "Alveolar positive; non-alveolar not FDR-supported", "Do not generalize across macrophages"],
  ["Low abundance", "Relative fold change without donor-level absolute context", "Donor median/IQR CP10K, quasibinomial prevalence, empirical-logit sensitivity, and positive-cell CP10K", "Ciliated prevalence decreased; alveolar-macrophage prevalence increased; positive-cell abundance was not different in either", "Prevalence-dependent interpretation"],
  ["Source-library structure", "Unmodeled technical confounding", "Disease x library table, MDS, estimability audit", "Library identifiers donor-specific and disease-nested", "Disease and source-library cannot be separated"],
  ["Raw-matrix verification", "First 5,000-cell spot check", "Full 692,789,348-coordinate stream", "2,363,040 target entries and 964 sample totals matched exactly", "Complete source verification"],
  ["Composition", "Adjustment interpreted as explanation", "VIF, bootstrap, marker and cell-type leave-outs", "Reference- and cohort-dependent", "Sensitivity, not causal proof"],
  ["Clean-room reproducibility", "Scripts depended on private legacy paths or derived target inputs", "Manifest-driven public inputs, bundled target manifest/hash, and analysis-root-only document builders", "All 12 public inputs verified; full target panel and 964 sample totals matched exactly", "Package can be rerun without the legacy project tree"],
];

const largeFiles = workbook.worksheets.add("Large_Result_Files");
largeFiles.getRange("A1:F4").values = [
  ["Result", "Relative path", "Rows", "Columns", "Compressed bytes", "Workbook handling"],
  ["Whole-lung cohort-level transcriptome effects", "results/whole_lung/whole_lung_transcriptome_Hedges_g_from_source_data.csv.gz", 40902, 9, 1935464, "Delivered as compressed CSV; complete meta table is included in this workbook"],
  ["Whole-lung transcriptome Hartung-Knapp meta-analysis", "results/whole_lung/whole_lung_transcriptome_meta_HK_from_source_data.csv.gz", 13632, 14, 1255749, "Included in this workbook and delivered as compressed CSV"],
  ["Full-transcriptome cell-type edgeR results at >=20 cells", "results/lung_scrna_full/GSE136831_full_transcriptome_edgeR_primary20_all_genes.csv.gz", 85057, 14, 5037391, "Delivered as compressed CSV; FASN effects and donor values are included in this workbook"],
];

async function readCsv(path) {
  const bytes = await fs.readFile(path);
  return path.endsWith(".gz") ? zlib.gunzipSync(bytes).toString("utf8") : bytes.toString("utf8");
}

const imports = [
  ["Input_Manifest", `${root}/input_manifest/input_manifest_v1.3.1_sha256.csv`],
  ["AT2_Sample_QC", `${root}/results/AT2/GSE245965_AT2_sample_QC.csv`],
  ["AT2_All_Genes", `${root}/results/AT2/GSE245965_AT2_raw_count_voom_all_genes.csv`],
  ["AT2_GSEA", `${root}/results/AT2/GSE245965_AT2_GSEA_full.csv`],
  ["AT2_ORA", `${root}/results/AT2/GSE245965_AT2_ORA_FDR_defined_DEGs.csv`],
  ["AT2_LOO_DEGs", `${root}/results/AT2/GSE245965_AT2_DEG_leave_one_sample_out.csv`],
  ["AT2_FASN_LOO", `${root}/results/AT2/GSE245965_AT2_FASN_leave_one_sample_out.csv`],
  ["AT2_LOO_Pathways", `${root}/results/AT2/GSE245965_AT2_selected_pathway_stability.csv`],
  ["Focal_Candidates", `${root}/results/whole_lung/genes_meeting_focal_selection_criteria.csv`],
  ["WholeLung_Transcript_Meta", `${root}/results/whole_lung/whole_lung_transcriptome_meta_HK_from_source_data.csv.gz`],
  ["FASN_Transcript_Calibration", `${root}/results/whole_lung/FASN_transcriptome_wide_calibration.csv`],
  ["FASN_Cohort", `${root}/results/whole_lung/FASN_cohort_effects_from_source_data.csv`],
  ["FASN_Meta", `${root}/results/whole_lung/FASN_meta_HK_prediction_interval.csv`],
  ["FASN_LOO_Cohort", `${root}/results/whole_lung/FASN_leave_one_cohort_out_HK.csv`],
  ["RawCEL_vs_Series", `${root}/results/whole_lung/FASN_raw_CEL_vs_series_matrix_sensitivity.csv`],
  ["scRNA_Sample_Manifest", `${root}/results/lung_scrna_full/GSE136831_full_pseudobulk_sample_manifest.csv`],
  ["scRNA_TotalUMI_Check", `${root}/results/lung_scrna_full/GSE136831_sample_total_umi_validation.csv`],
  ["scRNA_FASN_Localization", `${root}/results/lung_scrna_full/GSE136831_FASN_fine_celltype_localization.csv`],
  ["scRNA_Disease_Absolute", `${root}/results/lung_scrna_full/GSE136831_FASN_disease_specific_absolute_expression.csv`],
  ["scRNA_Donor_Absolute", `${root}/results/lung_scrna_full/GSE136831_FASN_donor_level_absolute_summary_primary20.csv`],
  ["scRNA_Donor_Detection", `${root}/results/lung_scrna_full/GSE136831_FASN_donor_detection_summary.csv`],
  ["scRNA_Hurdle", `${root}/results/lung_scrna_full/GSE136831_FASN_hurdle_style_sensitivity.csv`],
  ["scRNA_FASN_Full_Effects", `${root}/results/lung_scrna_full/GSE136831_FASN_full_transcriptome_threshold_sensitivity.csv`],
  ["scRNA_Full_Donor_Values", `${root}/results/lung_scrna_full/GSE136831_FASN_full_transcriptome_donor_values.csv.gz`],
  ["scRNA_Library_Dist", `${root}/results/lung_scrna_full/GSE136831_disease_by_library_distribution.csv`],
  ["scRNA_Donor_Libraries", `${root}/results/lung_scrna_full/GSE136831_donor_library_manifest.csv`],
  ["scRNA_Library_Estim", `${root}/results/lung_scrna_full/GSE136831_source_library_adjustment_estimability.csv`],
  ["scRNA_TechRep_Sens", `${root}/results/lung_scrna_full/GSE136831_FASN_technical_replication_sensitivity.csv`],
  ["scRNA_MDS", `${root}/results/lung_scrna_full/GSE136831_primary20_pseudobulk_MDS_coordinates.csv`],
  ["scRNA_Targeted_OffsetFix", `${root}/results/lung_scrna/GSE136831_FASN_raw_pseudobulk_offset_fixed_threshold_sensitivity.csv`],
  ["Composition_Models", `${root}/results/composition/FASN_composition_models_source_reanalysis.csv`],
  ["Deconv_VIF", `${root}/results/composition/NNLS_model_VIF_and_condition_number.csv`],
  ["Deconv_Bootstrap", `${root}/results/composition/NNLS_FASN_bootstrap_CI.csv`],
  ["Deconv_LOO_Marker", `${root}/results/composition/NNLS_leave_one_marker_out.csv`],
  ["Deconv_LOO_Celltype", `${root}/results/composition/NNLS_leave_one_celltype_out.csv`],
];

for (const [sheetName, filePath] of imports) {
  const csvText = await readCsv(filePath);
  const imported = await Workbook.fromCSV(csvText, { sheetName });
  const importedSheet = imported.worksheets.getItem(sheetName);
  const importedRange = importedSheet.getUsedRange(true);
  const sheet = workbook.worksheets.add(sheetName);
  if (importedRange) sheet.getRange(importedRange.address).values = importedRange.values;
}

for (const [sheetName, fileName] of [
  ["scRNA_Source_Validation", "GSE136831_full_source_validation.json"],
  ["scRNA_Stream_Summary", "GSE136831_streaming_aggregation_summary.json"],
  ["scRNA_Preparation", "GSE136831_full_pseudobulk_preparation.json"],
]) {
  const value = JSON.parse(await fs.readFile(`${root}/results/lung_scrna_full/${fileName}`, "utf8"));
  const rows = [["Metric", "Value"], ...Object.entries(value).map(([key, item]) => [key, Array.isArray(item) ? item.join("; ") : item])];
  const sheet = workbook.worksheets.add(sheetName);
  sheet.getRangeByIndexes(0, 0, rows.length, 2).values = rows;
}

const software = workbook.worksheets.add("Software_Versions");
const softwareLines = (await fs.readFile(`${root}/software_versions/software_versions.txt`, "utf8"))
  .split(/\r?\n/).filter(Boolean).map((line) => {
    const index = line.indexOf("=");
    return index >= 0 ? [line.slice(0, index), line.slice(index + 1)] : [line, ""];
  });
software.getRangeByIndexes(0, 0, softwareLines.length + 1, 2).values = [["Software", "Version"], ...softwareLines];

const headerFill = "#234E70";
const stripeFill = "#F4F7F9";
const borderColor = "#D4DEE7";

for (let i = 0; i < workbook.worksheets.items.length; i += 1) {
  const sheet = workbook.worksheets.getItemAt(i);
  sheet.showGridLines = false;
  const used = sheet.getUsedRange(true);
  if (!used) continue;
  const rowCount = used.rowCount ?? used.values.length;
  const colCount = used.columnCount ?? used.values[0].length;
  used.format.font = { name: "Arial", size: 9 };
  used.format.verticalAlignment = "top";
  used.format.wrapText = true;
  used.format.borders = { insideHorizontal: { style: "thin", color: borderColor } };
  const firstRow = used.getRow(0);
  firstRow.format = {
    fill: headerFill,
    font: { bold: true, color: "#FFFFFF", size: 10, name: "Arial" },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "all", style: "thin", color: borderColor },
  };
  firstRow.format.rowHeight = 30;
  sheet.freezePanes.freezeRows(1);
  if (rowCount <= 250) {
    for (let row = 1; row < rowCount; row += 2) {
      sheet.getRangeByIndexes(row, 0, 1, colCount).format.fill = stripeFill;
    }
  }
  used.format.autofitColumns();
  if (rowCount <= 250) {
    used.format.autofitRows();
    for (let row = 1; row < rowCount; row += 1) {
      const rowRange = sheet.getRangeByIndexes(row, 0, 1, colCount);
      if (rowRange.format.rowHeight > 72) rowRange.format.rowHeight = 72;
    }
  }
  for (let column = 0; column < colCount; column += 1) {
    const range = sheet.getRangeByIndexes(0, column, rowCount, 1);
    const current = range.format.columnWidth;
    if (current > 38) range.format.columnWidth = 38;
    if (current < 10) range.format.columnWidth = 10;
  }
  if (sheet.name === "README") {
    sheet.getRange("A:A").format.columnWidth = 22;
    sheet.getRange("B:B").format.columnWidth = 112;
    for (const row of [4, 6, 9, 13, 14]) {
      sheet.getRange(`A${row}:B${row}`).format.rowHeight = 34;
    }
  }
  if (sheet.name === "Dataset_Metadata") {
    sheet.getRange("A:C").format.columnWidth = 24;
    sheet.getRange("G:H").format.columnWidth = 42;
  }
  if (sheet.name === "Technical_Audit") {
    sheet.getRange("A:B").format.columnWidth = 26;
    sheet.getRange("C:E").format.columnWidth = 46;
  }
  if (sheet.name === "scRNA_Hurdle") {
    sheet.getRange("B:B").format.columnWidth = 52;
    sheet.getRange("C:C").format.columnWidth = 34;
  }
  if (rowCount <= 250) {
    used.format.autofitRows();
    for (let row = 1; row < rowCount; row += 1) {
      const rowRange = sheet.getRangeByIndexes(row, 0, 1, colCount);
      if (rowRange.format.rowHeight > 72) rowRange.format.rowHeight = 72;
    }
  }
  if (sheet.name === "README") {
    for (const row of [4, 6, 9, 13, 14]) {
      sheet.getRange(`A${row}:B${row}`).format.rowHeight = 34;
    }
  }
}

for (const sheet of workbook.worksheets.items) {
  const used = sheet.getUsedRange(true);
  const rowCount = used.rowCount ?? used.values.length;
  const colCount = used.columnCount ?? used.values[0].length;
  const previewRows = Math.min(rowCount, 24);
  const previewCols = Math.min(colCount, 12);
  const range = sheet.getRangeByIndexes(0, 0, previewRows, previewCols);
  const preview = await workbook.render({ sheetName: sheet.name, range: range.address, scale: 1, format: "png" });
  await fs.writeFile(`${previewDir}/${sheet.name}.png`, new Uint8Array(await preview.arrayBuffer()));
}

const overview = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 5000,
  tableMaxRows: 4,
  tableMaxCols: 5,
  tableMaxCellChars: 60,
});
await fs.writeFile(`${previewDir}/workbook_inspect.ndjson`, overview.ndjson, "utf8");

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
});
await fs.writeFile(`${previewDir}/formula_error_scan.ndjson`, errors.ndjson, "utf8");

const exported = await SpreadsheetFile.exportXlsx(workbook);
await exported.save(output);
console.log(`Wrote ${output} with ${workbook.worksheets.items.length} sheets`);
