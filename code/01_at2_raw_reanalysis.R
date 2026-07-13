suppressPackageStartupMessages({
  library(edgeR)
  library(limma)
  library(fgsea)
  library(msigdbr)
  library(clusterProfiler)
  library(data.table)
  library(ggplot2)
  library(patchwork)
})

set.seed(20260710)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript 01_at2_raw_reanalysis.R <raw-data-root> <analysis-root>")
}
raw_data_dir <- normalizePath(args[[1]], mustWork = TRUE)
analysis_dir <- normalizePath(args[[2]], mustWork = TRUE)
input_file <- file.path(
  raw_data_dir, "GSE245965",
  "GSE245965_AT2_IPF_v_NORMAL_bulkRNAseq_tableofcounts_FINAL-1.csv.gz"
)
out_dir <- file.path(analysis_dir, "results", "AT2")
fig_dir <- file.path(analysis_dir, "figures", "supplementary")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

counts_df <- read.csv(gzfile(input_file), check.names = FALSE)
gene_id <- as.character(counts_df[[1]])
counts <- as.matrix(counts_df[, -1, drop = FALSE])
mode(counts) <- "numeric"
rownames(counts) <- gene_id
sample_name <- colnames(counts)
group <- factor(
  ifelse(grepl("^IPF", sample_name, ignore.case = TRUE), "IPF", "Control"),
  levels = c("Control", "IPF")
)

run_voom <- function(count_matrix, group_factor) {
  y <- DGEList(counts = count_matrix, group = group_factor)
  keep <- filterByExpr(y, group = group_factor)
  y <- y[keep, , keep.lib.sizes = FALSE]
  y <- calcNormFactors(y)
  design <- model.matrix(~ group_factor)
  v <- voom(y, design, plot = FALSE, save.plot = TRUE)
  fit <- eBayes(lmFit(v, design), trend = FALSE, robust = TRUE)
  tt <- topTable(fit, coef = "group_factorIPF", number = Inf, sort.by = "none")
  tt$gene_id <- rownames(tt)
  tt$status <- ifelse(
    tt$adj.P.Val < 0.05 & tt$logFC > 1, "Up",
    ifelse(tt$adj.P.Val < 0.05 & tt$logFC < -1, "Down", "NS")
  )
  list(y = y, design = design, voom = v, fit = fit, table = tt)
}

full <- run_voom(counts, group)
res <- full$table
write.csv(res, file.path(out_dir, "GSE245965_AT2_raw_count_voom_all_genes.csv"), row.names = FALSE)

sample_qc <- data.frame(
  sample = sample_name,
  group = as.character(group),
  raw_library_size = colSums(counts),
  retained_library_size = full$y$samples$lib.size,
  norm_factor = full$y$samples$norm.factors,
  effective_library_size = full$y$samples$lib.size * full$y$samples$norm.factors,
  stringsAsFactors = FALSE
)
write.csv(sample_qc, file.path(out_dir, "GSE245965_AT2_sample_QC.csv"), row.names = FALSE)

pca <- prcomp(t(full$voom$E), center = TRUE, scale. = FALSE)
pca_var <- 100 * (pca$sdev^2 / sum(pca$sdev^2))
pca_df <- data.frame(
  sample = rownames(pca$x),
  group = as.character(group[match(rownames(pca$x), sample_name)]),
  PC1 = pca$x[, 1],
  PC2 = pca$x[, 2],
  stringsAsFactors = FALSE
)
pca_df$sample_short <- c("IPF1", "IPF2", "CTL1", "CTL2", "CTL3")[match(pca_df$sample, sample_name)]
write.csv(pca_df, file.path(out_dir, "GSE245965_AT2_PCA_coordinates.csv"), row.names = FALSE)

cor_mat <- cor(full$voom$E, method = "pearson")
write.csv(cor_mat, file.path(out_dir, "GSE245965_AT2_sample_correlation.csv"))

hallmark <- msigdbr(species = "Homo sapiens", collection = "H")
reactome <- msigdbr(species = "Homo sapiens", collection = "C2", subcollection = "CP:REACTOME")
gobp <- msigdbr(species = "Homo sapiens", collection = "C5", subcollection = "GO:BP")

pathways <- split(
  as.character(c(hallmark$ncbi_gene, reactome$ncbi_gene)),
  c(hallmark$gs_name, reactome$gs_name)
)
term2gene_ora <- unique(rbind(
  data.frame(term = reactome$gs_name, gene = as.character(reactome$ncbi_gene)),
  data.frame(term = gobp$gs_name, gene = as.character(gobp$ncbi_gene))
))

run_gsea <- function(tt, label) {
  ranked <- tt$t
  names(ranked) <- as.character(tt$gene_id)
  ranked <- ranked[is.finite(ranked) & !is.na(names(ranked)) & nzchar(names(ranked))]
  ranked <- sort(ranked[!duplicated(names(ranked))], decreasing = TRUE)
  fg <- fgseaMultilevel(pathways = pathways, stats = ranked, minSize = 10, maxSize = 500, eps = 0)
  fg <- as.data.frame(fg)
  fg$analysis <- label
  fg$leadingEdge <- vapply(fg$leadingEdge, paste, collapse = ";", FUN.VALUE = character(1))
  fg[order(fg$padj, -abs(fg$NES)), ]
}

gsea_full <- run_gsea(res, "Full")
write.csv(gsea_full, file.path(out_dir, "GSE245965_AT2_GSEA_full.csv"), row.names = FALSE)

universe <- unique(as.character(res$gene_id))
up_genes <- as.character(res$gene_id[res$adj.P.Val < 0.05 & res$logFC > 1])
down_genes <- as.character(res$gene_id[res$adj.P.Val < 0.05 & res$logFC < -1])

run_ora <- function(genes, direction) {
  fit <- enricher(
    genes,
    universe = universe,
    TERM2GENE = term2gene_ora,
    pvalueCutoff = 1,
    qvalueCutoff = 1,
    minGSSize = 10,
    maxGSSize = 500
  )
  out <- as.data.frame(fit)
  if (nrow(out) == 0) return(data.frame())
  out$direction <- direction
  out
}

ora <- rbind(run_ora(up_genes, "Up"), run_ora(down_genes, "Down"))
if (nrow(ora) > 0) ora <- ora[order(ora$p.adjust), ]
write.csv(ora, file.path(out_dir, "GSE245965_AT2_ORA_FDR_defined_DEGs.csv"), row.names = FALSE)

loo_tables <- list(gsea_full)
loo_de_counts <- list(data.frame(
  omitted_sample = "None",
  n_control = sum(group == "Control"),
  n_ipf = sum(group == "IPF"),
  measured_genes = nrow(res),
  up_FDR05_logFC1 = length(up_genes),
  down_FDR05_logFC1 = length(down_genes)
))
fasn_full <- res[as.character(res$gene_id) == "2194", , drop = FALSE]
loo_fasn <- list(data.frame(
  omitted_sample = "None",
  n_control = sum(group == "Control"),
  n_ipf = sum(group == "IPF"),
  FASN_log2FC = fasn_full$logFC,
  FASN_P = fasn_full$P.Value,
  FASN_FDR = fasn_full$adj.P.Val,
  direction = ifelse(fasn_full$logFC < 0, "Down", "Up")
))
for (i in seq_along(sample_name)) {
  keep_samples <- seq_along(sample_name) != i
  sub_group <- droplevels(group[keep_samples])
  sub_fit <- run_voom(counts[, keep_samples, drop = FALSE], sub_group)
  label <- paste0("Omit_", sample_name[i])
  loo_tables[[length(loo_tables) + 1]] <- run_gsea(sub_fit$table, label)
  loo_de_counts[[length(loo_de_counts) + 1]] <- data.frame(
    omitted_sample = sample_name[i],
    n_control = sum(sub_group == "Control"),
    n_ipf = sum(sub_group == "IPF"),
    measured_genes = nrow(sub_fit$table),
    up_FDR05_logFC1 = sum(sub_fit$table$adj.P.Val < 0.05 & sub_fit$table$logFC > 1),
    down_FDR05_logFC1 = sum(sub_fit$table$adj.P.Val < 0.05 & sub_fit$table$logFC < -1)
  )
  fasn_i <- sub_fit$table[as.character(sub_fit$table$gene_id) == "2194", , drop = FALSE]
  loo_fasn[[length(loo_fasn) + 1]] <- data.frame(
    omitted_sample = sample_name[i],
    n_control = sum(sub_group == "Control"),
    n_ipf = sum(sub_group == "IPF"),
    FASN_log2FC = fasn_i$logFC,
    FASN_P = fasn_i$P.Value,
    FASN_FDR = fasn_i$adj.P.Val,
    direction = ifelse(fasn_i$logFC < 0, "Down", "Up")
  )
}
loo_gsea <- rbindlist(loo_tables, fill = TRUE)
loo_counts <- rbindlist(loo_de_counts, fill = TRUE)
loo_fasn <- rbindlist(loo_fasn, fill = TRUE)
write.csv(loo_gsea, file.path(out_dir, "GSE245965_AT2_GSEA_leave_one_sample_out.csv"), row.names = FALSE)
write.csv(loo_counts, file.path(out_dir, "GSE245965_AT2_DEG_leave_one_sample_out.csv"), row.names = FALSE)
write.csv(loo_fasn, file.path(out_dir, "GSE245965_AT2_FASN_leave_one_sample_out.csv"), row.names = FALSE)

selected_pathways <- c(
  "HALLMARK_EPITHELIAL_MESENCHYMAL_TRANSITION",
  "REACTOME_EXTRACELLULAR_MATRIX_ORGANIZATION",
  "REACTOME_KERATINIZATION",
  "REACTOME_COLLAGEN_FORMATION",
  "REACTOME_CHOLESTEROL_BIOSYNTHESIS",
  "HALLMARK_FATTY_ACID_METABOLISM",
  "REACTOME_SURFACTANT_METABOLISM",
  "REACTOME_UNFOLDED_PROTEIN_RESPONSE_UPR",
  "REACTOME_METABOLISM_OF_PHOSPHOLIPIDS",
  "HALLMARK_OXIDATIVE_PHOSPHORYLATION"
)
selected_loo <- as.data.table(loo_gsea)[pathway %in% selected_pathways]
selected_loo[, pathway_label := gsub("^(HALLMARK_|REACTOME_)", "", pathway)]
selected_loo[, pathway_label := gsub("_", " ", pathway_label)]
selected_loo[, analysis := factor(analysis, levels = c("Full", paste0("Omit_", sample_name)))]
write.csv(selected_loo, file.path(out_dir, "GSE245965_AT2_selected_pathway_stability.csv"), row.names = FALSE)

summary_df <- data.frame(
  metric = c(
    "Raw genes", "Voom retained genes", "Upregulated DEGs",
    "Downregulated DEGs", "ORA terms", "GSEA pathways",
    "GSEA FDR<0.05 positive", "GSEA FDR<0.05 negative"
  ),
  value = c(
    nrow(counts), nrow(res), length(up_genes), length(down_genes), nrow(ora), nrow(gsea_full),
    sum(gsea_full$padj < 0.05 & gsea_full$NES > 0, na.rm = TRUE),
    sum(gsea_full$padj < 0.05 & gsea_full$NES < 0, na.rm = TRUE)
  )
)
write.csv(summary_df, file.path(out_dir, "GSE245965_AT2_reanalysis_summary.csv"), row.names = FALSE)

control_col <- "#0072B2"
ipf_col <- "#D55E00"
group_cols <- c(Control = control_col, IPF = ipf_col)

p_lib <- ggplot(sample_qc, aes(x = sample, y = raw_library_size / 1e6, fill = group)) +
  geom_col(width = 0.7) +
  scale_fill_manual(values = group_cols) +
  labs(x = NULL, y = "Raw library size (million)", title = "A  Library size") +
  theme_classic(base_size = 9) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1), legend.position = "none",
        plot.title = element_text(face = "bold"))

p_pca <- ggplot(pca_df, aes(PC1, PC2, color = group, label = sample_short)) +
  geom_point(size = 3) +
  geom_text(nudge_y = 0.35, size = 2.5, check_overlap = TRUE) +
  scale_color_manual(values = group_cols) +
  labs(
    x = sprintf("PC1 (%.1f%%)", pca_var[1]),
    y = sprintf("PC2 (%.1f%%)", pca_var[2]),
    title = "B  PCA"
  ) +
  theme_classic(base_size = 9) +
  theme(legend.position = "none", plot.title = element_text(face = "bold"))

short_names <- setNames(c("IPF1", "IPF2", "CTL1", "CTL2", "CTL3"), sample_name)
dimnames(cor_mat) <- list(short_names[rownames(cor_mat)], short_names[colnames(cor_mat)])
cor_dt <- as.data.table(as.table(cor_mat))
setnames(cor_dt, c("sample_x", "sample_y", "correlation"))
p_cor <- ggplot(cor_dt, aes(sample_x, sample_y, fill = correlation)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.2f", correlation)), size = 2.3) +
  scale_fill_gradient(low = "white", high = "#2166AC", limits = c(min(cor_mat), 1)) +
  labs(x = NULL, y = NULL, title = "C  Sample correlation", fill = "Pearson r") +
  coord_equal() +
  theme_minimal(base_size = 8) +
  theme(axis.text.x = element_text(angle = 40, hjust = 1), panel.grid = element_blank(),
        plot.title = element_text(face = "bold"), legend.position = "none")

voom_points <- data.frame(mean_log_count = full$voom$voom.xy$x, sqrt_sd = full$voom$voom.xy$y)
voom_line <- data.frame(mean_log_count = full$voom$voom.line$x, sqrt_sd = full$voom$voom.line$y)
p_voom <- ggplot(voom_points, aes(mean_log_count, sqrt_sd)) +
  geom_point(size = 0.35, alpha = 0.25, color = "#666666") +
  geom_line(data = voom_line, color = ipf_col, linewidth = 0.9) +
  labs(x = "Mean log2 count", y = "Square-root residual SD", title = "D  Voom mean-variance trend") +
  theme_classic(base_size = 9) +
  theme(plot.title = element_text(face = "bold"))

qc_plot <- (p_lib | p_pca) / (p_cor | p_voom)
ggsave(file.path(fig_dir, "Figure_S1_AT2_QC.pdf"), qc_plot, width = 7.1, height = 6.0, units = "in")
ggsave(file.path(fig_dir, "Figure_S1_AT2_QC.png"), qc_plot, width = 7.1, height = 6.0, units = "in", dpi = 300)
ggsave(file.path(fig_dir, "Figure_S1_AT2_QC.tiff"), qc_plot, width = 7.1, height = 6.0, units = "in", dpi = 600, compression = "lzw")

p_stability <- ggplot(selected_loo, aes(analysis, reorder(pathway_label, NES), fill = NES)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.2f", NES)), size = 2.2) +
  scale_fill_gradient2(low = control_col, mid = "white", high = ipf_col, midpoint = 0) +
  labs(x = NULL, y = NULL, fill = "NES", title = "AT2 pathway stability after leaving out one sample") +
  theme_minimal(base_size = 8.5) +
  theme(
    axis.text.x = element_text(angle = 35, hjust = 1),
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold")
  )
ggsave(file.path(fig_dir, "Figure_S2_AT2_leave_one_out_GSEA.pdf"), p_stability, width = 7.1, height = 5.2, units = "in")
ggsave(file.path(fig_dir, "Figure_S2_AT2_leave_one_out_GSEA.png"), p_stability, width = 7.1, height = 5.2, units = "in", dpi = 300)
ggsave(file.path(fig_dir, "Figure_S2_AT2_leave_one_out_GSEA.tiff"), p_stability, width = 7.1, height = 5.2, units = "in", dpi = 600, compression = "lzw")

message("AT2 raw-count reanalysis completed: ", normalizePath(out_dir))
