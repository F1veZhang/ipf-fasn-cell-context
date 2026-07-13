# v1.3.1 changes

This patch release freezes the v1.3 scientific analysis and changes only
release hygiene, caption clarity, and automated validation.

## Public-release hygiene

- Replaced machine-specific paths in the GSE136831 preparation summary with
  raw-data-root and analysis-root relative paths.
- Rebuilt the supplementary workbook so `scRNA_Preparation` contains no local
  Windows directory information.
- Removed the redundant lowercase intermediate `figures/` tree; only the
  versioned final figure tree is distributed.
- Upgraded the release audit to verify cached Word `SEQ` values for Figure 1-4
  and Table 1 directly from OOXML.
- Added the pseudo-log axis explanation to the Figure 4 caption and slightly
  reduced the Figure 1B scRNA-seq box font for additional margin.

## Reproducibility

- Replaced legacy private-path inputs with a uniform raw-data root.
- Added manifest-driven download, size verification, SHA-256 verification, and
  safe CEL archive extraction.
- Removed the package-external manuscript-builder dependency.
- Reconstructed the 62-gene validation panel directly from the complete raw
  matrix and confirmed all 2,363,040 entries by canonical SHA-256.
- Verified full-transcriptome total UMI exactly in all 964 donor-cell-type
  samples.
- Disabled the persistent .NET shared compiler during pipeline builds to avoid
  Windows clean-run hangs.

## Statistics

- Promoted donor-stratified quasibinomial detection-prevalence models to the
  primary low-abundance sensitivity.
- Retained unweighted empirical-logit models as secondary sensitivity analyses.
- Replaced positive-cell raw-count intensity with mean cell-level CP10K among
  FASN-positive cells.
- Added donor-level median/IQR CP10K and detection-rate summaries at the primary
  20-cell threshold.

## Figures and manuscript

- Corrected Figure 1C so whole-lung calibration precedes FASN selection.
- Rebuilt Figure 4A from donor-level absolute summaries.
- Added the monocyte cell-type FDR label to Figure 4B.
- Replaced `prespecified` with explicit reproducible/exploratory selection
  language.
- Updated low-abundance results, Figure 4 caption, references 24 and 25, and
  Word-style counts.
- Added the sample composition to the Figure 2 caption.
- Marked additional cell-context experiments as deferred rather than required
  for the current release.

## Workbook

- Expanded the supplement from 42 to 43 sheets with donor-level absolute
  expression.
- Updated the technical audit and low-abundance sheets for quasibinomial and
  normalized positive-cell results.
- Rechecked all sheets for common formula-error tokens; none were found.
