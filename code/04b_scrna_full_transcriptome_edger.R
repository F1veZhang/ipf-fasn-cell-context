suppressPackageStartupMessages({
  library(data.table)
  library(edgeR)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript 04b_scrna_full_transcriptome_edger.R <analysis-root>")
}
analysis_dir <- normalizePath(args[[1]], mustWork = TRUE)
input_dir <- file.path(analysis_dir, "results", "lung_scrna_full")
out_dir <- input_dir

celltype_order <- c(
  "AT2", "AT1", "Aberrant basaloid", "Basal", "Club", "Ciliated", "Goblet",
  "Ionocyte", "PNEC", "Mesothelial", "Fibroblast", "Myofibroblast", "Pericyte",
  "Smooth muscle", "Alveolar macrophage", "Non-alveolar macrophage", "Monocyte",
  "Endothelial", "T/NK", "B/plasma"
)
thresholds <- c(5L, 20L, 50L)

genes <- fread(file.path(input_dir, "GSE136831_gene_manifest.tsv"))
samples <- fread(file.path(input_dir, "GSE136831_full_pseudobulk_sample_manifest.tsv"))
sample_totals <- fread(file.path(input_dir, "GSE136831_full_pseudobulk_counts.sample_totals.tsv"))
samples <- merge(samples, sample_totals, by = "sample_index", all.x = TRUE, sort = FALSE)
setorder(samples, sample_index)
if (any(samples$metadata_total_umi != samples$raw_matrix_total_umi)) {
  stop("Raw-matrix and metadata total UMI values do not match")
}

connection <- file(file.path(input_dir, "GSE136831_full_pseudobulk_counts.bin"), "rb")
gene_count <- readBin(connection, integer(), n = 1L, size = 4L, endian = "little")
sample_count <- readBin(connection, integer(), n = 1L, size = 4L, endian = "little")
raw_vector <- readBin(
  connection, integer(), n = as.double(gene_count) * sample_count,
  size = 4L, signed = TRUE, endian = "little"
)
close(connection)
stopifnot(gene_count == nrow(genes), sample_count == nrow(samples))
sample_by_gene <- matrix(raw_vector, nrow = sample_count, ncol = gene_count)
rm(raw_vector)
gc()

gene_keys <- make.unique(ifelse(is.na(genes$symbol) | genes$symbol == "", genes$ensembl, genes$symbol))
fasn_index <- which(genes$symbol == "FASN")
if (length(fasn_index) != 1L) stop("Expected exactly one FASN row")

analyze_one <- function(celltype, threshold) {
  sm <- samples[fine_celltype == celltype & n_cells >= threshold]
  n_control <- sm[Disease_Identity == "Control", uniqueN(Subject_Identity)]
  n_ipf <- sm[Disease_Identity == "IPF", uniqueN(Subject_Identity)]
  if (n_control < 3L || n_ipf < 3L) return(NULL)

  sample_rows <- sm$sample_index
  mat <- t(sample_by_gene[sample_rows, , drop = FALSE])
  rownames(mat) <- gene_keys
  colnames(mat) <- sm$sample_id
  group <- factor(sm$Disease_Identity, levels = c("Control", "IPF"))
  design <- model.matrix(~ group)

  y <- DGEList(counts = mat, lib.size = sm$raw_matrix_total_umi, group = group)
  keep <- filterByExpr(y, design = design)
  keep[fasn_index] <- TRUE
  y <- y[keep, , keep.lib.sizes = TRUE]
  y <- calcNormFactors(y, method = "TMM")
  mds <- NULL
  if (threshold == 20L) {
    mds_fit <- plotMDS(y, top = 500, plot = FALSE)
    mds <- data.table(
      sample_id = sm$sample_id,
      Subject_Identity = sm$Subject_Identity,
      Disease_Identity = sm$Disease_Identity,
      fine_celltype = celltype,
      n_cells = sm$n_cells,
      n_libraries = sm$n_libraries,
      library_ids = sm$library_ids,
      library_replication = sm$library_replication,
      MDS1 = mds_fit$x,
      MDS2 = mds_fit$y
    )
  }
  fit <- tryCatch({
    y <- estimateDisp(y, design, robust = TRUE)
    glmQLFit(y, design, robust = TRUE)
  }, error = function(e) {
    y <- estimateDisp(y, design, robust = FALSE)
    glmQLFit(y, design, robust = FALSE)
  })
  qlf <- glmQLFTest(fit, coef = "groupIPF")
  tt <- as.data.table(topTags(qlf, n = Inf, sort.by = "none")$table, keep.rownames = "gene_key")
  tt[, row_index := match(gene_key, gene_keys)]
  tt[, `:=`(ensembl = genes$ensembl[row_index], symbol = genes$symbol[row_index])]
  tt[, `:=`(
    fine_celltype = celltype,
    min_cells = threshold,
    n_control = n_control,
    n_ipf = n_ipf,
    tested_genes = nrow(tt)
  )]

  fasn <- tt[symbol == "FASN"]
  if (nrow(fasn) == 0L) {
    fasn <- data.table(
      logFC = NA_real_, logCPM = NA_real_, F = NA_real_, PValue = NA_real_, FDR = NA_real_
    )
  }
  f_value <- fasn$F[[1]]
  standard_error <- if (is.finite(f_value) && f_value > 0) abs(fasn$logFC[[1]]) / sqrt(f_value) else NA_real_
  df_total <- if (!is.null(qlf$df.total)) qlf$df.total[match("FASN", rownames(qlf$table))] else NA_real_
  critical <- if (length(df_total) == 1L && is.finite(df_total)) qt(0.975, df = df_total) else 1.96
  effect <- data.table(
    fine_celltype = celltype,
    min_cells = threshold,
    n_control = n_control,
    n_ipf = n_ipf,
    edgeR_log2FC = fasn$logFC[[1]],
    edgeR_SE_approx = standard_error,
    edgeR_CI_low = fasn$logFC[[1]] - critical * standard_error,
    edgeR_CI_high = fasn$logFC[[1]] + critical * standard_error,
    edgeR_P = fasn$PValue[[1]],
    edgeR_gene_FDR = fasn$FDR[[1]],
    tested_genes = nrow(tt)
  )

  fasn_counts <- mat[fasn_index, ]
  effective_library <- y$samples$lib.size * y$samples$norm.factors
  donor_values <- data.table(
    sample_id = sm$sample_id,
    Subject_Identity = sm$Subject_Identity,
    Disease_Identity = sm$Disease_Identity,
    fine_celltype = celltype,
    min_cells = threshold,
    n_cells = sm$n_cells,
    total_umi = sm$raw_matrix_total_umi,
    FASN_raw_count = as.numeric(fasn_counts),
    FASN_log2_CPM = log2(1e6 * (as.numeric(fasn_counts) + 0.5) / (effective_library + 1))
  )

  technical_effect <- data.table(
    fine_celltype = celltype,
    min_cells = threshold,
    model = "Disease only",
    estimable = TRUE,
    edgeR_log2FC = fasn$logFC[[1]],
    edgeR_P = fasn$PValue[[1]],
    note = "Primary donor-level model"
  )
  replication <- factor(sm$library_replication, levels = c("Single library", "Multiple libraries"))
  design_replication <- model.matrix(~ replication + group)
  replication_estimable <- nlevels(droplevels(replication)) == 2L &&
    qr(design_replication)$rank == ncol(design_replication)
  if (replication_estimable) {
    y_rep <- DGEList(counts = mat, lib.size = sm$raw_matrix_total_umi, group = group)
    y_rep <- y_rep[keep, , keep.lib.sizes = TRUE]
    y_rep <- calcNormFactors(y_rep, method = "TMM")
    fit_rep <- tryCatch({
      y_rep <- estimateDisp(y_rep, design_replication, robust = TRUE)
      glmQLFit(y_rep, design_replication, robust = TRUE)
    }, error = function(e) {
      y_rep <- estimateDisp(y_rep, design_replication, robust = FALSE)
      glmQLFit(y_rep, design_replication, robust = FALSE)
    })
    qlf_rep <- glmQLFTest(fit_rep, coef = "groupIPF")
    tt_rep <- as.data.table(topTags(qlf_rep, n = Inf, sort.by = "none")$table, keep.rownames = "gene_key")
    fasn_rep <- tt_rep[gene_key == gene_keys[fasn_index]]
    technical_effect <- rbind(
      technical_effect,
      data.table(
        fine_celltype = celltype,
        min_cells = threshold,
        model = "Disease + multiple-library indicator",
        estimable = TRUE,
        edgeR_log2FC = fasn_rep$logFC[[1]],
        edgeR_P = fasn_rep$PValue[[1]],
        note = "Sensitivity for technical replication density; not a source/library fixed-effect adjustment"
      )
    )
  } else {
    technical_effect <- rbind(
      technical_effect,
      data.table(
        fine_celltype = celltype,
        min_cells = threshold,
        model = "Disease + multiple-library indicator",
        estimable = FALSE,
        edgeR_log2FC = NA_real_, edgeR_P = NA_real_,
        note = "Not estimable because technical replication did not vary or the design was rank-deficient"
      )
    )
  }
  list(
    effect = effect, donor_values = donor_values, all_genes = tt,
    mds = mds, technical_effect = technical_effect
  )
}

results <- list()
for (threshold in thresholds) {
  for (celltype in celltype_order) {
    result <- analyze_one(celltype, threshold)
    if (!is.null(result)) results[[paste(celltype, threshold, sep = "__")]] <- result
  }
}

effects <- rbindlist(lapply(results, `[[`, "effect"), fill = TRUE)
effects[, edgeR_BH_across_celltypes := p.adjust(edgeR_P, method = "BH"), by = min_cells]
donor_values <- rbindlist(lapply(results, `[[`, "donor_values"), fill = TRUE)
primary_results <- rbindlist(
  lapply(results[grepl("__20$", names(results))], `[[`, "all_genes"),
  fill = TRUE
)
mds_coordinates <- rbindlist(lapply(results, `[[`, "mds"), fill = TRUE)
technical_effects <- rbindlist(lapply(results, `[[`, "technical_effect"), fill = TRUE)

library_estimability <- unique(effects[, .(fine_celltype, min_cells, n_control, n_ipf)])
library_estimability[, `:=`(
  source_library_fixed_effect_estimable = FALSE,
  reason = paste0(
    "Library_Identity is unique or nearly unique to each donor and fully nested within disease; ",
    "no shared source/center variable is available, so source-library and disease effects cannot be separated."
  )
)]

fwrite(effects, file.path(out_dir, "GSE136831_FASN_full_transcriptome_threshold_sensitivity.csv"))
fwrite(donor_values, file.path(out_dir, "GSE136831_FASN_full_transcriptome_donor_values.csv.gz"))
fwrite(primary_results, file.path(out_dir, "GSE136831_full_transcriptome_edgeR_primary20_all_genes.csv.gz"))
fwrite(mds_coordinates, file.path(out_dir, "GSE136831_primary20_pseudobulk_MDS_coordinates.csv"))
fwrite(technical_effects, file.path(out_dir, "GSE136831_FASN_technical_replication_sensitivity.csv"))
fwrite(library_estimability, file.path(out_dir, "GSE136831_source_library_adjustment_estimability.csv"))
message("Full-transcriptome donor pseudobulk completed for ", nrow(effects), " estimable comparisons")
