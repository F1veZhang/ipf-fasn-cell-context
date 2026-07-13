suppressPackageStartupMessages({
  library(data.table)
  library(metafor)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript 02b_whole_lung_transcriptome_meta.R <analysis-root>")
}
analysis_dir <- normalizePath(args[[1]], mustWork = TRUE)
matrix_dir <- file.path(analysis_dir, "derived_matrices")
out_dir <- file.path(analysis_dir, "results", "whole_lung")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cohorts <- list(
  GSE150910 = readRDS(file.path(matrix_dir, "GSE150910_logCPM.rds")),
  GSE110147 = readRDS(file.path(matrix_dir, "GSE110147_rawCEL_RMA_gene.rds")),
  GSE24206 = readRDS(file.path(matrix_dir, "GSE24206_rawCEL_RMA_gene.rds"))
)

common_genes <- Reduce(intersect, lapply(cohorts, function(x) rownames(x$expression)))
common_genes <- sort(unique(toupper(common_genes)))

cohort_effects <- function(obj, dataset, genes) {
  expr <- obj$expression[genes, , drop = FALSE]
  group <- as.character(obj$group[colnames(expr)])
  keep_samples <- !is.na(group) & group %in% c("Control", "IPF")
  expr <- expr[, keep_samples, drop = FALSE]
  group <- group[keep_samples]
  control <- expr[, group == "Control", drop = FALSE]
  ipf <- expr[, group == "IPF", drop = FALSE]
  n0 <- ncol(control)
  n1 <- ncol(ipf)
  df <- n0 + n1 - 2
  mean0 <- rowMeans(control)
  mean1 <- rowMeans(ipf)
  var0 <- apply(control, 1, var)
  var1 <- apply(ipf, 1, var)
  pooled_var <- ((n0 - 1) * var0 + (n1 - 1) * var1) / df
  J <- 1 - 3 / (4 * df - 1)
  g <- J * (mean1 - mean0) / sqrt(pooled_var)
  variance <- (n1 + n0) / (n1 * n0) + g^2 / (2 * df)
  data.table(
    dataset = dataset,
    gene = genes,
    n_control = n0,
    n_ipf = n1,
    hedges_g = g,
    variance = variance,
    SE = sqrt(variance),
    ci_low = g - 1.96 * sqrt(variance),
    ci_high = g + 1.96 * sqrt(variance)
  )[is.finite(hedges_g) & is.finite(variance) & variance > 0]
}

effects <- rbindlist(lapply(names(cohorts), function(dataset) {
  cohort_effects(cohorts[[dataset]], dataset, common_genes)
}))
fwrite(effects, file.path(out_dir, "whole_lung_transcriptome_Hedges_g_from_source_data.csv.gz"))

genes_to_test <- Reduce(intersect, lapply(split(effects$gene, effects$dataset), unique))
meta_rows <- vector("list", length(genes_to_test))
for (index in seq_along(genes_to_test)) {
  gene_i <- genes_to_test[[index]]
  x <- effects[gene == gene_i]
  fit <- tryCatch(
    rma(yi = x$hedges_g, vi = x$variance, method = "REML", test = "knha"),
    error = function(e) NULL
  )
  if (!is.null(fit)) {
    pred <- tryCatch(predict(fit), error = function(e) NULL)
    meta_rows[[index]] <- data.table(
      gene = gene_i,
      k = nrow(x),
      meta_hedges_g = as.numeric(fit$b[[1]]),
      meta_SE = fit$se,
      meta_p = fit$pval,
      meta_CI_low = fit$ci.lb,
      meta_CI_high = fit$ci.ub,
      prediction_low = if (is.null(pred)) NA_real_ else pred$pi.lb,
      prediction_high = if (is.null(pred)) NA_real_ else pred$pi.ub,
      tau2 = fit$tau2,
      I2 = fit$I2
    )
  }
  if (index %% 2000L == 0L) message("Meta-analyzed ", index, " / ", length(genes_to_test), " genes")
}
meta <- rbindlist(meta_rows, fill = TRUE)
meta[, meta_FDR := p.adjust(meta_p, method = "BH")]
meta[, p_rank := frank(meta_p, ties.method = "min")]
meta[, p_percentile := 100 * (1 - (p_rank - 1) / .N)]
setorder(meta, meta_p)
fwrite(meta, file.path(out_dir, "whole_lung_transcriptome_meta_HK_from_source_data.csv.gz"))

fasn <- meta[gene == "FASN"]
fasn[, tested_genes := nrow(meta)]
fasn[, discoveries_FDR05 := sum(meta$meta_FDR < 0.05, na.rm = TRUE)]
fasn[, discoveries_FDR10 := sum(meta$meta_FDR < 0.10, na.rm = TRUE)]
fwrite(fasn, file.path(out_dir, "FASN_transcriptome_wide_calibration.csv"))
fwrite(fasn, file.path(out_dir, "FASN_meta_HK_prediction_interval.csv"))

message("Transcriptome-wide meta-analysis completed for ", nrow(meta), " genes")
