args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript run_all.R <raw-data-root> <analysis-root>")
}

raw_data_root <- normalizePath(args[[1]], mustWork = TRUE)
analysis_root <- normalizePath(args[[2]], mustWork = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1]]), mustWork = TRUE)
code_root <- file.path(dirname(script_path), "code")
rscript <- file.path(R.home("bin"), "Rscript")
python <- Sys.getenv("PYTHON", unset = "python")
dotnet <- Sys.getenv("DOTNET", unset = "dotnet")

run <- function(command, arguments) {
  message("Running: ", command, " ", paste(shQuote(arguments), collapse = " "))
  status <- system2(command, shQuote(arguments))
  if (!identical(status, 0L)) stop("Command failed with status ", status)
}

run(rscript, c(file.path(code_root, "01_at2_raw_reanalysis.R"), raw_data_root, analysis_root))
run(rscript, c(file.path(code_root, "02_whole_lung_raw_reanalysis.R"), raw_data_root, analysis_root))
run(rscript, c(file.path(code_root, "02b_whole_lung_transcriptome_meta.R"), analysis_root))
run(rscript, c(file.path(code_root, "02c_focal_candidate_audit.R"), analysis_root))
run(python, c(file.path(code_root, "03_prepare_full_scrna_pseudobulk.py"),
              "--raw-data-root", raw_data_root, "--analysis-root", analysis_root,
              "--target-manifest", file.path(analysis_root, "reference", "GSE136831_target_gene_manifest.csv")))

aggregator_project <- file.path(code_root, "scrna_mtx_aggregator", "scrna_mtx_aggregator.csproj")
run(dotnet, c("build", aggregator_project, "-c", "Release",
              "--disable-build-servers", "-p:UseSharedCompilation=false"))
output_root <- file.path(analysis_root, "results", "lung_scrna_full")
aggregator_dll <- file.path(code_root, "scrna_mtx_aggregator", "bin", "Release", "net9.0",
                            "scrna_mtx_aggregator.dll")
run(dotnet, c(
  aggregator_dll,
  file.path(raw_data_root, "GSE136831", "GSE136831_RawCounts_Sparse.mtx.gz"),
  file.path(output_root, "GSE136831_cell_to_sample_index.txt"),
  file.path(output_root, "GSE136831_target_row_indices.txt"),
  file.path(output_root, "GSE136831_full_pseudobulk_counts.bin"),
  file.path(output_root, "GSE136831_target_panel_reconstructed_from_full_mtx.tsv.gz"),
  file.path(output_root, "GSE136831_streaming_aggregation_summary.json")
))
run(python, c(file.path(code_root, "03c_validate_full_scrna_outputs.py"),
              "--analysis-root", analysis_root))
run(python, c(file.path(code_root, "03d_summarize_fasn_absolute_expression.py"),
              "--raw-data-root", raw_data_root, "--analysis-root", analysis_root))
run(python, c(file.path(code_root, "03_lung_scrna_raw_pseudobulk.py"),
              "--raw-data-root", raw_data_root, "--analysis-root", analysis_root))
run(rscript, c(file.path(code_root, "04_scrna_edger_pseudobulk.R"), analysis_root))
run(rscript, c(file.path(code_root, "04b_scrna_full_transcriptome_edger.R"), analysis_root))
run(rscript, c(file.path(code_root, "04c_scrna_confounds_and_low_abundance.R"), analysis_root))
run(rscript, c(file.path(code_root, "05_composition_stress_tests.R"), analysis_root))
run(rscript, c(file.path(code_root, "06b_make_final_figures_v1_3_1.R"), analysis_root))

message("Analytical pipeline completed. Build the supplement and manuscript using the commands in README.md.")
quit(save = "no", status = 0L, runLast = FALSE)
