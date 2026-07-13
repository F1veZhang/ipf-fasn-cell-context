suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(patchwork)
  library(AnnotationDbi)
  library(org.Hs.eg.db)
  library(scales)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: Rscript 06b_make_final_figures_v1_3_1.R <analysis-root>")
analysis_dir <- normalizePath(args[[1]], mustWork = TRUE)
results_dir <- file.path(analysis_dir, "results")
figure_root <- file.path(analysis_dir, "Figures_v1.3.1_20260712")
main_dir <- file.path(figure_root, "Main")
supp_dir <- file.path(figure_root, "Supplementary")
source_dir <- file.path(analysis_dir, "figure_source_data")
dir.create(main_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(supp_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(source_dir, recursive = TRUE, showWarnings = FALSE)

blue <- "#1677A6"
orange <- "#D65F2E"
green <- "#238B68"
charcoal <- "#4F5458"
light_grey <- "#D8DADD"

save_formats <- function(plot, directory, stem, width, height) {
  ggsave(file.path(directory, paste0(stem, ".pdf")), plot, width = width, height = height,
         units = "in", device = cairo_pdf)
  ggsave(file.path(directory, paste0(stem, ".png")), plot, width = width, height = height,
         units = "in", dpi = 300)
  ggsave(file.path(directory, paste0(stem, ".tiff")), plot, width = width, height = height,
         units = "in", dpi = 600, compression = "lzw")
}

theme_panel <- function(base_size = 8.5) {
  theme_classic(base_size = base_size) +
    theme(
      text = element_text(family = "Arial"),
      plot.title = element_text(face = "bold", size = base_size + 0.7, hjust = 0),
      plot.subtitle = element_text(size = base_size - 0.4, color = charcoal),
      axis.text = element_text(color = "#303438"),
      axis.title = element_text(color = "#202428"),
      legend.title = element_text(size = base_size - 0.4),
      legend.text = element_text(size = base_size - 0.7),
      plot.margin = margin(5, 6, 5, 5)
    )
}

architecture_panel <- function(title, boxes, arrows = NULL, xlim = c(0, 10), ylim = c(0, 5)) {
  p <- ggplot() + coord_cartesian(xlim = xlim, ylim = ylim, clip = "off") +
    labs(title = title) + theme_void(base_size = 9.5) +
    theme(
      text = element_text(family = "Arial"),
      plot.title = element_text(face = "bold", size = 10, margin = margin(b = 2)),
      plot.margin = margin(4, 5, 4, 5)
    )
  for (box in boxes) {
    p <- p + annotate(
      "rect", xmin = box$xmin, xmax = box$xmax, ymin = box$ymin, ymax = box$ymax,
      fill = box$fill, color = box$color, linewidth = 0.65
    ) + annotate(
      "text", x = (box$xmin + box$xmax) / 2, y = (box$ymin + box$ymax) / 2,
      label = box$label, size = box$size, fontface = box$face, lineheight = 1.05,
      family = "Arial", color = "#202428"
    )
  }
  if (!is.null(arrows)) {
    for (a in arrows) {
      p <- p + annotate(
        "segment", x = a$x, xend = a$xend, y = a$y, yend = a$yend,
        linewidth = 0.65, color = charcoal,
        arrow = grid::arrow(length = grid::unit(0.11, "inches"), type = "closed")
      )
    }
  }
  p
}

# Figure 1: three-panel architecture with a single evidence progression.
p1a <- architecture_panel(
  "A  Scientific question",
  list(
    list(xmin = 0.4, xmax = 4.2, ymin = 1.6, ymax = 3.6, fill = "#F2F3F4", color = charcoal,
         label = "Whole-lung\nFASN decrease", size = 3.7, face = "bold"),
    list(xmin = 6.0, xmax = 9.6, ymin = 2.8, ymax = 4.4, fill = "#E8F2F7", color = blue,
         label = "Cell-intrinsic\nregulation", size = 3.4, face = "plain"),
    list(xmin = 6.0, xmax = 9.6, ymin = 0.6, ymax = 2.2, fill = "#FBEDE7", color = orange,
         label = "Cell composition\nor compartment", size = 3.05, face = "plain")
  ),
  list(list(x = 4.3, xend = 5.8, y = 2.75, yend = 3.55),
       list(x = 4.3, xend = 5.8, y = 2.45, yend = 1.45))
)

p1b <- architecture_panel(
  "B  Source-level datasets",
  list(
    list(xmin = 0.3, xmax = 3.1, ymin = 1.0, ymax = 4.2, fill = "#E8F2F7", color = blue,
         label = "Purified AT2\nraw counts\n2 IPF | 3 control", size = 2.7, face = "plain"),
    list(xmin = 3.6, xmax = 6.4, ymin = 1.0, ymax = 4.2, fill = "#F2F3F4", color = charcoal,
         label = "Whole lung\ncounts + raw CEL\n3 cohorts", size = 2.7, face = "plain"),
    list(xmin = 6.9, xmax = 9.7, ymin = 1.0, ymax = 4.2, fill = "#EAF5EF", color = green,
         label = "Lung scRNA-seq\nfull raw UMI matrix\n32 IPF | 28 control", size = 2.40, face = "plain")
  )
)

p1c <- architecture_panel(
  "C  Evidence progression",
  list(
    list(xmin = 0.05, xmax = 1.85, ymin = 1.15, ymax = 3.95, fill = "white", color = blue,
         label = "AT2 pathway\n+ explicit rule\n6 genes", size = 2.05, face = "bold"),
    list(xmin = 2.15, xmax = 3.95, ymin = 1.15, ymax = 3.95, fill = "white", color = charcoal,
         label = "Transcriptome-wide\nwhole-lung\ncalibration", size = 2.10, face = "bold"),
    list(xmin = 4.25, xmax = 6.05, ymin = 1.15, ymax = 3.95, fill = "white", color = orange,
         label = "FASN selected\nafter whole-lung\ncalibration", size = 2.05, face = "bold"),
    list(xmin = 6.35, xmax = 8.15, ymin = 1.15, ymax = 3.95, fill = "white", color = green,
         label = "Full-transcriptome\ndonor\npseudobulk", size = 2.10, face = "bold"),
    list(xmin = 8.45, xmax = 10.25, ymin = 1.15, ymax = 3.95, fill = "white", color = orange,
         label = "Reference-dependent\ncomposition\nsensitivity", size = 1.95, face = "bold")
  ),
  list(list(x = 1.88, xend = 2.08, y = 2.55, yend = 2.55),
       list(x = 3.98, xend = 4.18, y = 2.55, yend = 2.55),
       list(x = 6.08, xend = 6.28, y = 2.55, yend = 2.55),
       list(x = 8.18, xend = 8.38, y = 2.55, yend = 2.55)),
  xlim = c(0, 10.3)
)

figure1 <- (p1a | p1b) / p1c + plot_layout(heights = c(0.56, 0.44))
save_formats(figure1, main_dir, "Figure1_study_architecture", 7.1, 4.7)
fwrite(data.table(
  dataset = c("GSE245965", "GSE150910", "GSE110147", "GSE24206", "GSE136831"),
  input = c("raw counts", "raw counts", "raw CEL", "raw CEL", "full raw UMI matrix"),
  role = c("purified AT2 discovery", "whole-lung synthesis", "whole-lung synthesis",
           "whole-lung synthesis", "full-transcriptome donor pseudobulk")
), file.path(source_dir, "Figure1_source_data.csv"))

# Figure 2: AT2 gene and pathway programs.
at2 <- fread(file.path(results_dir, "AT2", "GSE245965_AT2_raw_count_voom_all_genes.csv"))
at2[, neg_log10_FDR := -log10(pmax(adj.P.Val, 1e-300))]
at2[, status := factor(status, levels = c("NS", "Down", "Up"))]
at2[, symbol := AnnotationDbi::mapIds(
  org.Hs.eg.db, keys = as.character(gene_id), keytype = "ENTREZID", column = "SYMBOL", multiVals = "first"
)]
label_genes <- unique(c("FASN", head(at2[status != "NS" & !is.na(symbol)][order(-abs(t))]$symbol, 7)))
label_dt <- at2[symbol %in% label_genes]
p2a <- ggplot(at2, aes(logFC, neg_log10_FDR, color = status)) +
  geom_point(size = 0.55, alpha = 0.52) +
  geom_vline(xintercept = c(-1, 1), linetype = "dashed", color = "#999999", linewidth = 0.42) +
  geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "#999999", linewidth = 0.42) +
  geom_text(data = label_dt, aes(label = symbol), size = 2.2, color = "#202428",
            check_overlap = TRUE, nudge_y = 0.12) +
  scale_color_manual(values = c(NS = "#BFC2C5", Down = blue, Up = orange)) +
  labs(x = "IPF-control log2 fold change", y = "-log10 BH-FDR", color = NULL,
       title = "A  Purified AT2 differential expression") +
  theme_panel(8.3) + theme(legend.position = "bottom")

gsea <- fread(file.path(results_dir, "AT2", "GSE245965_AT2_GSEA_full.csv"))
wanted <- c(
  "HALLMARK_EPITHELIAL_MESENCHYMAL_TRANSITION",
  "REACTOME_EXTRACELLULAR_MATRIX_ORGANIZATION",
  "REACTOME_KERATINIZATION",
  "REACTOME_COLLAGEN_FORMATION",
  "REACTOME_CHOLESTEROL_BIOSYNTHESIS",
  "HALLMARK_FATTY_ACID_METABOLISM",
  "REACTOME_SURFACTANT_METABOLISM",
  "REACTOME_UNFOLDED_PROTEIN_RESPONSE_UPR",
  "REACTOME_PHOSPHOLIPID_METABOLISM",
  "HALLMARK_OXIDATIVE_PHOSPHORYLATION"
)
gsea_plot <- gsea[pathway %in% wanted]
gsea_plot[, label := tools::toTitleCase(tolower(gsub("_", " ", gsub("^(HALLMARK_|REACTOME_)", "", pathway))))]
gsea_plot[label == "Unfolded Protein Response Upr", label := "Unfolded Protein Response (UPR)"]
gsea_plot[, label := factor(label, levels = label[order(NES)])]
gsea_plot[, direction := factor(ifelse(NES > 0, "Positive NES", "Negative NES"),
                                levels = c("Negative NES", "Positive NES"))]
gsea_plot[, minus_log10_FDR := -log10(pmax(padj, 1e-300))]
p2b <- ggplot(gsea_plot, aes(NES, label)) +
  geom_vline(xintercept = 0, color = "#777777", linewidth = 0.45) +
  geom_segment(aes(x = 0, xend = NES, yend = label), color = "#C7C9CB", linewidth = 0.55) +
  geom_point(aes(size = minus_log10_FDR, color = direction), alpha = 0.92) +
  scale_color_manual(values = c("Negative NES" = blue, "Positive NES" = orange)) +
  scale_size_continuous(range = c(2.5, 6.2)) +
  labs(x = "GSEA normalized enrichment score", y = NULL, size = "-log10 FDR",
       color = NULL, title = "B  Structural and metabolic programs") +
  theme_panel(8.3) + theme(legend.position = "right")
figure2 <- p2a + p2b + plot_layout(widths = c(0.42, 0.58))
save_formats(figure2, main_dir, "Figure2_AT2_structural_metabolic_divergence", 7.1, 3.85)
fwrite(at2, file.path(source_dir, "Figure2A_AT2_volcano_source_data.csv"))
fwrite(gsea_plot, file.path(source_dir, "Figure2B_AT2_GSEA_source_data.csv"))

# Figure 3: FASN whole-lung synthesis plus transcriptome-wide calibration.
fasn <- fread(file.path(results_dir, "whole_lung", "FASN_cohort_effects_from_source_data.csv"))
fasn_meta <- fread(file.path(results_dir, "whole_lung", "FASN_meta_HK_prediction_interval.csv"))
forest <- rbindlist(list(
  fasn[, .(label = dataset, estimate = hedges_g, low = ci_low, high = ci_high, type = "Cohort")],
  fasn_meta[, .(label = "Hartung-Knapp pooled", estimate = meta_hedges_g,
                low = meta_CI_low, high = meta_CI_high, type = "Pooled")]
))
forest[, label := factor(label, levels = rev(c("GSE150910", "GSE110147", "GSE24206", "Hartung-Knapp pooled")))]
p3a <- ggplot(forest, aes(estimate, label, color = type)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "#888888") +
  geom_errorbar(aes(xmin = low, xmax = high), orientation = "y", width = 0.15, linewidth = 0.65) +
  geom_point(size = 2.2) +
  scale_color_manual(values = c(Cohort = blue, Pooled = orange)) +
  labs(x = "IPF-control Hedges' g", y = NULL, color = NULL, title = "A  FASN cohort effects") +
  theme_panel(8.3) + theme(legend.position = "bottom")

meta <- fread(file.path(results_dir, "whole_lung", "whole_lung_transcriptome_meta_HK_from_source_data.csv.gz"))
meta[, minus_log10_p := -log10(pmax(meta_p, 1e-300))]
meta[, focal := ifelse(gene == "FASN", "FASN", "Other genes")]
p3b <- ggplot(meta, aes(meta_hedges_g, minus_log10_p, color = focal)) +
  geom_point(data = meta[gene != "FASN"], size = 0.55, alpha = 0.34) +
  geom_point(data = meta[gene == "FASN"], size = 2.5) +
  geom_text(
    data = meta[gene == "FASN"],
    aes(label = paste0("FASN\nrank ", comma(p_rank), "/", comma(nrow(meta)))),
    color = "#202428", size = 2.3, nudge_y = 0.25, lineheight = 0.95
  ) +
  scale_color_manual(values = c("FASN" = orange, "Other genes" = "#AEB2B5")) +
  labs(x = "Pooled Hedges' g", y = "-log10 meta-analysis P", color = NULL,
       title = "B  Transcriptome-wide meta-analysis",
       subtitle = paste0(comma(nrow(meta)), " genes; 0 at BH-FDR < 0.10")) +
  theme_panel(8.3) + theme(legend.position = "none")

series <- fread(file.path(results_dir, "whole_lung", "FASN_raw_CEL_vs_series_matrix_sensitivity.csv"))
raw_pairs <- fasn[dataset %in% c("GSE110147", "GSE24206"),
                  .(dataset, source = "Raw CEL RMA", hedges_g, ci_low, ci_high)]
series_pairs <- series[, .(dataset, source = "GEO series matrix", hedges_g, ci_low, ci_high)]
preprocess <- rbindlist(list(raw_pairs, series_pairs))
preprocess[, dataset_label := factor(dataset, levels = c("GSE110147", "GSE24206"))]
preprocess[, source := factor(source, levels = c("Raw CEL RMA", "GEO series matrix"))]
p3c <- ggplot(preprocess, aes(hedges_g, dataset_label, color = source)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "#888888") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), orientation = "y",
                position = position_dodge(width = 0.48), width = 0.13) +
  geom_point(position = position_dodge(width = 0.48), size = 1.9) +
  scale_color_manual(values = c("Raw CEL RMA" = blue, "GEO series matrix" = charcoal)) +
  labs(x = "IPF-control Hedges' g", y = NULL, color = NULL,
       title = "C  Preprocessing sensitivity") +
  theme_panel(8.3) + theme(legend.position = "bottom")

loo <- fread(file.path(results_dir, "whole_lung", "FASN_leave_one_cohort_out_HK.csv"))
loo[, label := factor(paste("Omit", omitted_cohort), levels = rev(paste("Omit", omitted_cohort)))]
p3d <- ggplot(loo, aes(pooled_g, label)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "#888888") +
  geom_errorbar(aes(xmin = CI_low, xmax = CI_high), orientation = "y", width = 0.15, color = charcoal) +
  geom_point(size = 2.0, color = blue) +
  labs(x = "Pooled Hedges' g", y = NULL, title = "D  Leave-one-cohort-out FASN") +
  theme_panel(8.3)
figure3 <- (p3a | p3b) / (p3c | p3d) + plot_layout(heights = c(0.58, 0.42))
save_formats(figure3, main_dir, "Figure3_whole_lung_source_synthesis", 7.1, 5.65)
fwrite(forest, file.path(source_dir, "Figure3A_FASN_forest_source_data.csv"))
fwrite(meta, file.path(source_dir, "Figure3B_transcriptome_meta_source_data.csv.gz"))
fwrite(preprocess, file.path(source_dir, "Figure3C_preprocessing_sensitivity_source_data.csv"))
fwrite(loo, file.path(source_dir, "Figure3D_leave_one_cohort_out_source_data.csv"))

# Figure 4: donor-level absolute expression, full-transcriptome model estimates, and composition sensitivity.
localization <- fread(file.path(
  results_dir, "lung_scrna_full", "GSE136831_FASN_donor_level_absolute_summary_primary20.csv"
))
celltype_order <- c(
  "AT2", "AT1", "Aberrant basaloid", "Basal", "Club", "Ciliated", "Goblet",
  "Mesothelial", "Fibroblast", "Myofibroblast", "Pericyte", "Smooth muscle",
  "Alveolar macrophage", "Non-alveolar macrophage", "Monocyte", "Endothelial",
  "T/NK", "B/plasma", "Ionocyte", "PNEC"
)
localization[, fine_celltype := factor(fine_celltype, levels = rev(celltype_order))]
p4a <- ggplot(
  localization,
  aes(median_FASN_CP10K, fine_celltype,
      size = 100 * median_FASN_detection_rate, color = Disease_Identity)
) +
  geom_errorbar(
    aes(xmin = Q1_FASN_CP10K, xmax = Q3_FASN_CP10K), orientation = "y",
    position = position_dodge(width = 0.48), width = 0.11, linewidth = 0.55
  ) +
  geom_point(alpha = 0.94, position = position_dodge(width = 0.48)) +
  scale_x_continuous(
    trans = pseudo_log_trans(sigma = 0.01),
    breaks = c(0, 0.01, 0.03, 0.1, 0.3, 1),
    labels = c("0", "0.01", "0.03", "0.1", "0.3", "1")
  ) +
  scale_size_continuous(range = c(1.0, 5.4), breaks = c(5, 25, 50)) +
  scale_color_manual(values = c(Control = blue, IPF = orange)) +
  labs(
    x = "Median donor FASN CP10K (IQR)", y = NULL,
    size = "Median % detected", color = NULL,
    title = "A  Donor-level absolute expression",
    subtitle = "Primary threshold: >=20 cells per sample"
  ) +
  guides(
    size = guide_legend(nrow = 1, title.position = "left"),
    color = guide_legend(nrow = 1, title.position = "left")
  ) +
  theme_panel(7.8) +
  theme(
    legend.position = "bottom", legend.box = "vertical",
    legend.key.width = grid::unit(0.12, "inches"),
    legend.spacing.y = grid::unit(0.02, "inches")
  )

effects <- fread(file.path(results_dir, "lung_scrna_full", "GSE136831_FASN_full_transcriptome_threshold_sensitivity.csv"))
effects20 <- effects[min_cells == 20]
effects20[, support := ifelse(edgeR_BH_across_celltypes < 0.05, "Cell-type FDR < 0.05", "Not FDR-supported")]
effects20[, donor_label := paste0("n=", n_control, "/", n_ipf)]
effects20[, fdr_label := fifelse(
  fine_celltype %in% c("Ciliated", "Alveolar macrophage", "Monocyte"),
  paste0("FDR ", scientific(edgeR_BH_across_celltypes, digits = 2)), ""
)]
effects20[, fdr_x := fifelse(
  fine_celltype == "Alveolar macrophage", -2.50,
  fifelse(edgeR_log2FC < 0, edgeR_CI_low - 0.12, edgeR_CI_high + 0.12)
)]
effects20[, fdr_hjust := fifelse(
  fine_celltype == "Alveolar macrophage", 0,
  fifelse(edgeR_log2FC < 0, 1, 0)
)]
effect_order <- c(
  "AT2", "Ciliated", "Fibroblast", "Alveolar macrophage", "Non-alveolar macrophage",
  "Monocyte", "Endothelial", "T/NK", "B/plasma"
)
effects20[, fine_celltype := factor(fine_celltype, levels = rev(effect_order))]
p4b <- ggplot(effects20, aes(edgeR_log2FC, fine_celltype, color = support)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "#888888") +
  geom_errorbar(aes(xmin = edgeR_CI_low, xmax = edgeR_CI_high), orientation = "y", width = 0.13) +
  geom_point(size = 2.0) +
  geom_text(aes(x = 2.22, label = donor_label), color = charcoal, size = 2.0, hjust = 1) +
  geom_text(aes(x = fdr_x, label = fdr_label, hjust = fdr_hjust),
            color = charcoal, size = 1.85) +
  coord_cartesian(xlim = c(-2.65, 2.28), clip = "off") +
  scale_color_manual(values = c("Cell-type FDR < 0.05" = orange, "Not FDR-supported" = charcoal)) +
  labs(x = "edgeR IPF-control log2 fold change", y = NULL, color = NULL,
       title = "B  Full-transcriptome donor pseudobulk",
       subtitle = "Primary threshold: >=20 cells; n=control/IPF donors") +
  theme_panel(8.0) + theme(legend.position = "bottom")

models <- fread(file.path(results_dir, "composition", "FASN_composition_models_source_reanalysis.csv"))
models[, dataset_label := fifelse(dataset == "GSE110147", "GSE110147 (max VIF 27.4)", dataset)]
models[, dataset_label := factor(dataset_label,
                                 levels = c("GSE150910", "GSE110147 (max VIF 27.4)", "GSE24206"))]
models[, model := factor(model, levels = c("Unadjusted", "Marker-score adjusted", "NNLS adjusted"))]
p4c <- ggplot(models, aes(estimate, dataset_label, color = model)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "#888888") +
  geom_errorbar(aes(xmin = conf_low, xmax = conf_high), orientation = "y",
                position = position_dodge(width = 0.5), width = 0.13) +
  geom_point(position = position_dodge(width = 0.5), size = 1.9) +
  scale_color_manual(values = c("Unadjusted" = charcoal, "Marker-score adjusted" = blue,
                                "NNLS adjusted" = green)) +
  labs(x = "Standardized IPF coefficient for FASN", y = NULL, color = NULL,
       title = "C  Reference-dependent\nwhole-lung composition sensitivity") +
  guides(color = guide_legend(nrow = 2, byrow = TRUE)) +
  theme_panel(8.0) + theme(legend.position = "bottom")

figure4_right <- (p4b / p4c) + plot_layout(heights = c(0.54, 0.46))
figure4 <- (p4a | figure4_right) + plot_layout(widths = c(0.42, 0.58))
save_formats(figure4, main_dir, "Figure4_full_transcriptome_cell_context", 7.1, 6.35)
fwrite(localization, file.path(source_dir, "Figure4A_FASN_donor_absolute_expression_source_data.csv"))
fwrite(effects20, file.path(source_dir, "Figure4B_FASN_full_pseudobulk_source_data.csv"))
fwrite(models, file.path(source_dir, "Figure4C_composition_models_source_data.csv"))

# Updated supplementary figures for transcriptome-wide calibration and pseudobulk sensitivity.
p_s3 <- ggplot(meta, aes(p_rank, minus_log10_p)) +
  geom_point(size = 0.45, alpha = 0.35, color = "#AEB2B5") +
  geom_point(data = meta[gene == "FASN"], color = orange, size = 2.4) +
  geom_text(
    data = meta[gene == "FASN"],
    aes(label = paste0("FASN rank ", comma(p_rank), "/", comma(nrow(meta)))),
    color = charcoal, size = 2.5, nudge_y = 0.15
  ) +
  labs(x = "Transcriptome-wide meta-analysis P rank", y = "-log10 P",
       title = "Transcriptome-wide calibration of the FASN meta-analysis") +
  theme_panel(9)
save_formats(p_s3, supp_dir, "Figure_S3_transcriptome_wide_calibration", 7.1, 3.7)

donor <- fread(file.path(results_dir, "lung_scrna_full", "GSE136831_FASN_full_transcriptome_donor_values.csv.gz"))
donor20 <- donor[min_cells == 20 & fine_celltype %in% effect_order]
donor20[, fine_celltype := factor(fine_celltype, levels = effect_order)]
p_s4 <- ggplot(donor20, aes(Disease_Identity, FASN_log2_CPM, fill = Disease_Identity)) +
  geom_boxplot(width = 0.56, outlier.shape = NA, alpha = 0.75) +
  geom_jitter(width = 0.11, size = 0.65, alpha = 0.52) +
  facet_wrap(~ fine_celltype, scales = "free_y", ncol = 3) +
  scale_fill_manual(values = c(Control = blue, IPF = orange)) +
  labs(x = NULL, y = "FASN TMM-normalized log2 CPM",
       title = "Full-transcriptome donor pseudobulk values at the primary cell threshold") +
  theme_panel(8.4) + theme(legend.position = "none", axis.text.x = element_text(angle = 25, hjust = 1),
                           strip.background = element_rect(fill = "#F1F2F3", color = NA))
save_formats(p_s4, supp_dir, "Figure_S4_FASN_full_transcriptome_donor_pseudobulk", 7.1, 6.0)

effects[, threshold_label := factor(paste0(">=", min_cells, " cells"),
                                    levels = paste0(">=", c(5, 20, 50), " cells"))]
effects[, fine_celltype := factor(fine_celltype, levels = rev(celltype_order))]
p_s5 <- ggplot(effects, aes(edgeR_log2FC, fine_celltype, color = threshold_label)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "#888888") +
  geom_errorbar(aes(xmin = edgeR_CI_low, xmax = edgeR_CI_high), orientation = "y",
                position = position_dodge(width = 0.55), width = 0.13) +
  geom_point(position = position_dodge(width = 0.55), size = 1.65) +
  scale_color_manual(values = c(charcoal, blue, green)) +
  labs(x = "edgeR IPF-control log2 fold change", y = NULL, color = NULL,
       title = "FASN full-transcriptome cell-threshold sensitivity") +
  theme_panel(8.5) + theme(legend.position = "bottom")
save_formats(p_s5, supp_dir, "Figure_S5_FASN_full_transcriptome_threshold_sensitivity", 7.1, 6.1)

# Carry forward unaffected AT2 QC, AT2 leave-one-out, and composition diagnostics.
old_supp <- file.path(analysis_dir, "figures", "supplementary")
for (stem in c(
  "Figure_S1_AT2_QC", "Figure_S2_AT2_leave_one_out_GSEA",
  "Figure_S6_deconvolution_stress_tests", "Figure_S7_FASN_low_abundance_hurdle_sensitivity",
  "Figure_S8_GSE136831_pseudobulk_MDS"
)) {
  for (extension in c("pdf", "png", "tiff")) {
    file.copy(file.path(old_supp, paste0(stem, ".", extension)),
              file.path(supp_dir, paste0(stem, ".", extension)), overwrite = TRUE)
  }
}

fwrite(
  fread(file.path(results_dir, "whole_lung", "genes_meeting_focal_selection_criteria.csv")),
  file.path(source_dir, "Figure1C_focal_selection_source_data.csv")
)
message("Final v1.3.1 figures written to ", normalizePath(figure_root))
