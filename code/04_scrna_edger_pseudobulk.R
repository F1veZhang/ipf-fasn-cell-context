suppressPackageStartupMessages({
  library(data.table)
  library(edgeR)
  library(ggplot2)
  library(patchwork)
})

set.seed(20260710)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript 04_scrna_edger_pseudobulk.R <analysis-root>")
}
analysis_dir <- normalizePath(args[[1]], mustWork = TRUE)
input_dir <- file.path(analysis_dir, "results", "lung_scrna")
out_dir <- input_dir
fig_dir <- file.path(analysis_dir, "figures", "supplementary")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

pseudobulk <- fread(file.path(input_dir, "GSE136831_raw_target_gene_pseudobulk_long.csv"))
sample_meta <- fread(file.path(input_dir, "GSE136831_donor_celltype_sample_metadata.csv"))
celltype_order <- c(
  "AT2", "AT1", "Other epithelial", "Fibroblast", "Myofibroblast",
  "Macrophage", "Monocyte", "Endothelial", "T/NK", "B/plasma"
)
thresholds <- c(5L, 20L, 50L)

hedges_g <- function(x_ipf, x_control) {
  x_ipf <- x_ipf[is.finite(x_ipf)]
  x_control <- x_control[is.finite(x_control)]
  n1 <- length(x_ipf)
  n0 <- length(x_control)
  if (n1 < 2 || n0 < 2) return(c(g = NA_real_, variance = NA_real_))
  df <- n1 + n0 - 2
  sp2 <- ((n1 - 1) * var(x_ipf) + (n0 - 1) * var(x_control)) / df
  if (!is.finite(sp2) || sp2 <= 0) return(c(g = NA_real_, variance = NA_real_))
  d <- (mean(x_ipf) - mean(x_control)) / sqrt(sp2)
  J <- 1 - 3 / (4 * df - 1)
  g <- J * d
  variance <- (n1 + n0) / (n1 * n0) + g^2 / (2 * df)
  c(g = g, variance = variance)
}

bootstrap_g <- function(x_ipf, x_control, B = 2000) {
  obs <- hedges_g(x_ipf, x_control)[["g"]]
  if (!is.finite(obs) || length(x_ipf) < 3 || length(x_control) < 3) {
    return(c(low = NA_real_, high = NA_real_))
  }
  boots <- replicate(B, {
    hedges_g(sample(x_ipf, replace = TRUE), sample(x_control, replace = TRUE))[["g"]]
  })
  boots <- boots[is.finite(boots)]
  if (length(boots) < B * 0.8) return(c(low = NA_real_, high = NA_real_))
  unname(quantile(boots, c(0.025, 0.975), na.rm = TRUE))
}

test_one <- function(celltype, threshold) {
  sm <- sample_meta[major_celltype == celltype & n_cells >= threshold]
  n_control <- sm[Disease_Identity == "Control", uniqueN(Subject_Identity)]
  n_ipf <- sm[Disease_Identity == "IPF", uniqueN(Subject_Identity)]
  if (n_control < 3 || n_ipf < 3) return(NULL)

  genes <- sort(unique(pseudobulk$gene))
  grid <- CJ(gene = genes, sample_id = sm$sample_id, unique = TRUE)
  x <- merge(
    grid,
    pseudobulk[, .(gene, sample_id, raw_count)],
    by = c("gene", "sample_id"),
    all.x = TRUE
  )
  x[is.na(raw_count), raw_count := 0]
  wide <- dcast(x, gene ~ sample_id, value.var = "raw_count", fill = 0)
  mat <- as.matrix(wide[, -1])
  rownames(mat) <- wide$gene
  mat <- round(mat)
  sm <- sm[match(colnames(mat), sample_id)]
  group <- factor(sm$Disease_Identity, levels = c("Control", "IPF"))
  design <- model.matrix(~ group)

  y <- DGEList(counts = mat, lib.size = sm$total_umi, group = group)
  keep_gene <- rowSums(mat) > 0
  y <- y[keep_gene, , keep.lib.sizes = TRUE]
  y$samples$lib.size <- sm$total_umi
  y$samples$norm.factors <- 1
  fit <- tryCatch({
    y <- estimateDisp(y, design, robust = TRUE)
    glmQLFit(y, design, robust = TRUE)
  }, error = function(e) {
    y <- estimateDisp(y, design, robust = FALSE)
    glmQLFit(y, design, robust = FALSE)
  })
  qlf <- glmQLFTest(fit, coef = "groupIPF")
  tt <- topTags(qlf, n = Inf, sort.by = "none")$table
  tt$gene <- rownames(tt)
  tt <- as.data.table(tt)
  tt$selected_gene_FDR <- p.adjust(tt$PValue, method = "BH")
  tt$major_celltype <- celltype
  tt$min_cells <- threshold
  tt$n_control <- n_control
  tt$n_ipf <- n_ipf

  fasn_row <- sm[, .(
    sample_id, Subject_Identity, Disease_Identity, major_celltype,
    n_cells, total_umi
  )]
  fasn_counts <- data.table(sample_id = colnames(mat), raw_count = as.numeric(mat["FASN", ]))
  fasn_row <- merge(fasn_row, fasn_counts, by = "sample_id", all.x = TRUE)
  fasn_row[, CPM := 1e6 * (raw_count + 0.5) / (total_umi + 1)]
  fasn_row[, log2_CPM := log2(CPM)]
  eff <- hedges_g(
    fasn_row[Disease_Identity == "IPF", log2_CPM],
    fasn_row[Disease_Identity == "Control", log2_CPM]
  )
  boot <- bootstrap_g(
    fasn_row[Disease_Identity == "IPF", log2_CPM],
    fasn_row[Disease_Identity == "Control", log2_CPM]
  )
  analytic_se <- sqrt(eff[["variance"]])
  effect <- data.table(
    major_celltype = celltype,
    min_cells = threshold,
    n_control = n_control,
    n_ipf = n_ipf,
    hedges_g = eff[["g"]],
    analytic_SE = analytic_se,
    analytic_CI_low = eff[["g"]] - 1.96 * analytic_se,
    analytic_CI_high = eff[["g"]] + 1.96 * analytic_se,
    bootstrap_CI_low = boot[[1]],
    bootstrap_CI_high = boot[[2]],
    edgeR_logFC = tt[gene == "FASN", logFC],
    edgeR_P = tt[gene == "FASN", PValue],
    edgeR_selected_gene_FDR = tt[gene == "FASN", selected_gene_FDR]
  )
  list(all_genes = as.data.table(tt), fasn_effect = effect, fasn_values = fasn_row)
}

results <- list()
for (threshold in thresholds) {
  for (celltype in celltype_order) {
    ans <- test_one(celltype, threshold)
    if (!is.null(ans)) results[[paste(celltype, threshold, sep = "__")]] <- ans
  }
}

all_genes <- rbindlist(lapply(results, `[[`, "all_genes"), fill = TRUE)
fasn_effects <- rbindlist(lapply(results, `[[`, "fasn_effect"), fill = TRUE)
fasn_values <- rbindlist(lapply(results, `[[`, "fasn_values"), fill = TRUE, idcol = "analysis_id")
fasn_effects[, edgeR_BH_across_celltypes := p.adjust(edgeR_P, method = "BH"), by = min_cells]

write.csv(all_genes, file.path(out_dir, "GSE136831_raw_target_gene_edgeR_QL_offset_fixed_all_results.csv"), row.names = FALSE)
write.csv(fasn_effects, file.path(out_dir, "GSE136831_FASN_raw_pseudobulk_offset_fixed_threshold_sensitivity.csv"), row.names = FALSE)
write.csv(fasn_values, file.path(out_dir, "GSE136831_FASN_raw_pseudobulk_offset_fixed_donor_values.csv"), row.names = FALSE)

plot_values <- fasn_values[grepl("__20$", analysis_id)]
plot_values[, major_celltype := factor(major_celltype, levels = celltype_order)]
p_box <- ggplot(plot_values, aes(Disease_Identity, log2_CPM, fill = Disease_Identity)) +
  geom_boxplot(width = 0.58, outlier.shape = NA, alpha = 0.75) +
  geom_jitter(width = 0.12, size = 0.65, alpha = 0.55) +
  facet_wrap(~ major_celltype, scales = "free_y", ncol = 3) +
  scale_fill_manual(values = c(Control = "#0072B2", IPF = "#D55E00")) +
  labs(x = NULL, y = "FASN donor pseudobulk log2 CPM",
       title = "Raw-count donor pseudobulk with at least 20 cells per donor-cell type") +
  theme_classic(base_size = 8.5) +
  theme(
    legend.position = "none",
    axis.text.x = element_text(angle = 25, hjust = 1),
    strip.background = element_rect(fill = "#F0F0F0", color = NA),
    plot.title = element_text(face = "bold")
  )
ggsave(file.path(fig_dir, "Figure_S4_FASN_raw_donor_pseudobulk.pdf"), p_box, width = 7.1, height = 6.3, units = "in")
ggsave(file.path(fig_dir, "Figure_S4_FASN_raw_donor_pseudobulk.png"), p_box, width = 7.1, height = 6.3, units = "in", dpi = 300)
ggsave(file.path(fig_dir, "Figure_S4_FASN_raw_donor_pseudobulk.tiff"), p_box, width = 7.1, height = 6.3, units = "in", dpi = 600, compression = "lzw")

plot_effects <- copy(fasn_effects)
plot_effects[, major_celltype := factor(major_celltype, levels = rev(celltype_order))]
plot_effects[, threshold_label := factor(
  paste0(">=", min_cells, " cells"),
  levels = paste0(">=", thresholds, " cells")
)]
p_threshold <- ggplot(plot_effects, aes(hedges_g, major_celltype, color = threshold_label)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "#888888") +
  geom_errorbarh(
    aes(xmin = bootstrap_CI_low, xmax = bootstrap_CI_high),
    position = position_dodge(width = 0.55), height = 0.15
  ) +
  geom_point(position = position_dodge(width = 0.55), size = 1.8) +
  scale_color_manual(values = c("#666666", "#0072B2", "#009E73")) +
  labs(x = "IPF-control Hedges' g for FASN log2 CPM", y = NULL, color = NULL,
       title = "Donor-cell threshold sensitivity") +
  theme_classic(base_size = 9) +
  theme(legend.position = "bottom", plot.title = element_text(face = "bold"))
ggsave(file.path(fig_dir, "Figure_S5_FASN_cell_threshold_sensitivity.pdf"), p_threshold, width = 7.1, height = 4.7, units = "in")
ggsave(file.path(fig_dir, "Figure_S5_FASN_cell_threshold_sensitivity.png"), p_threshold, width = 7.1, height = 4.7, units = "in", dpi = 300)
ggsave(file.path(fig_dir, "Figure_S5_FASN_cell_threshold_sensitivity.tiff"), p_threshold, width = 7.1, height = 4.7, units = "in", dpi = 600, compression = "lzw")

message("Raw-count target-gene edgeR pseudobulk completed: ", normalizePath(out_dir))
