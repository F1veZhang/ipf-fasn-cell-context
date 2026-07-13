# Cell-Resolved Reanalysis of a Whole-Lung FASN Signal in IPF

This repository contains the executable analysis code, public-input manifests,
software environment records, and figure source data for release `v1.3.1`
(`2026-07-12`). The immutable full research compendium, including results,
figures, manuscript, supplement, and release manifest, is distributed through
Zenodo. Add the Zenodo DOI badge and record URL here after publication.

**Repository preparation and code curation:** Jianyi Zhang

## Scientific scope

FASN decreased directionally in three whole-lung cohorts, but the
transcriptome-wide Hartung-Knapp meta-analysis did not support corrected
discovery. In GSE136831, the low-abundance signal was compartment- and
prevalence-dependent, and whole-lung composition adjustments remained
reference- and cohort-dependent. This is a contextual case study rather than
evidence for a uniform mechanism or therapeutic target.

## Repository contents

- `run_all.R`: top-level analysis runner.
- `code/`: R, Python, .NET aggregation, figure, document, and workbook code.
- `figure_source_data/`: source tables used by Figures 1-4.
- `input_manifest/`: public input URLs, sizes, SHA-256 hashes, and clean paths.
- `software_versions/`: software and package version record.
- `reference/`: small GSE136831 integrity-check manifest required by the runner.
- `requirements.txt` and `renv.lock`: Python and R environment specifications.
- `CHANGELOG.md`: release history and v1.3.1 patch scope.
- `CITATION.cff`: machine-readable citation metadata.

Generated raw data, intermediate matrices, complete result tables, formatted
figures, manuscript files, and the supplement are intentionally excluded from
GitHub. They are available in the versioned Zenodo archive.

## Requirements

- R 4.4.1 with packages recorded in `renv.lock` and `software_versions/`.
- Python 3.11+ with packages in `requirements.txt`.
- .NET SDK 9 for the sparse-matrix streaming aggregator.
- Node.js with the workbook dependency recorded in `software_versions/` only
  for rebuilding the formatted supplementary workbook.

## Download and verify public inputs

From the repository root:

```powershell
python code/download_and_verify_inputs.py `
  --manifest input_manifest/input_manifest_v1.3.1_sha256.csv `
  --raw-data-root "<raw-data-root>"
```

To verify an existing download without extraction:

```powershell
python code/download_and_verify_inputs.py `
  --manifest input_manifest/input_manifest_v1.3.1_sha256.csv `
  --raw-data-root "<raw-data-root>" `
  --verify-only --no-extract
```

## Run the analyses

```powershell
$env:PYTHON = "python"
Rscript run_all.R "<raw-data-root>" .
```

The pipeline reprocesses purified AT2 data, whole-lung RNA-seq and raw CEL
cohorts, and the complete GSE136831 sparse UMI matrix. It then performs
transcriptome-wide meta-analysis, donor pseudobulk analyses, low-abundance
sensitivity analyses, composition stress tests, and final figure generation.

The GSE136831 integrity gate must report:

- processed nonzero entries: `692789348`;
- reconstructed target entries: `2363040`;
- canonical SHA-256:
  `8edf10c5f40359a14c6dc96427e866729c9f51a551699d4ce7d2501d53c87d8a`;
- exact total-UMI matches: `964/964`, maximum absolute delta `0`.

## Citation and archival copy

Use the repository's **Cite this repository** control, populated from
`CITATION.cff`. For the complete immutable research compendium, cite the Zenodo
record for `IPF_Source_Reanalysis_v1.3.1_20260712.zip`. After Zenodo publication,
replace this paragraph with the version DOI and add the concept DOI for the
project-level citation.

## Interpretation boundaries

- FASN was explicitly selected as a contextual case, not as a unique
  prespecified or transcriptome-wide significant target.
- GSE136831 libraries are donor-specific and nested within disease.
- Cell-resolved findings are internally threshold-consistent in one atlas, not
  externally replicated.
- Marker-score and NNLS estimates are sensitivity analyses, not measured cell
  fractions or causal mediation estimates.
