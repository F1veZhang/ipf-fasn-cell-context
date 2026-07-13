suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(patchwork)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript 04c_scrna_confounds_and_low_abundance.R <analysis-root>")
}
analysis_dir <- normalizePath(args[[1]], mustWork = TRUE)
input_dir <- file.path(analysis_dir, "results", "lung_scrna_full")
fig_dir <- file.path(analysis_dir, "figures", "supplementary")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

donor <- fread(file.path(input_dir, "GSE136831_FASN_donor_detection_summary.csv"))
mds <- fread(file.path(input_dir, "GSE136831_primary20_pseudobulk_MDS_coordinates.csv"))
donor <- donor[n_cells >= 20]

fit_lm_metric <- function(dt, metric, analysis_label, effect_scale) {
  n_control <- dt[Disease_Identity == "Control", uniqueN(Subject_Identity)]
  n_ipf <- dt[Disease_Identity == "IPF", uniqueN(Subject_Identity)]
  if (n_control < 3L || n_ipf < 3L) return(NULL)
  formula_i <- as.formula(paste(metric, "~ factor(Disease_Identity, levels = c('Control', 'IPF'))"))
  fit <- lm(formula_i, data = dt)
  coefficient_name <- grep("IPF", names(coef(fit)), value = TRUE)
  if (length(coefficient_name) != 1L) return(NULL)
  ci <- confint(fit, coefficient_name, level = 0.95)
  data.table(
    fine_celltype = dt$fine_celltype[[1]],
    analysis = analysis_label,
    effect_scale = effect_scale,
    n_control = n_control,
    n_ipf = n_ipf,
    IPF_minus_control_effect = unname(coef(fit)[coefficient_name]),
    CI_low = ci[1],
    CI_high = ci[2],
    P = summary(fit)$coefficients[coefficient_name, "Pr(>|t|)"]
  )
}

fit_quasibinomial <- function(dt) {
  n_control <- dt[Disease_Identity == "Control", uniqueN(Subject_Identity)]
  n_ipf <- dt[Disease_Identity == "IPF", uniqueN(Subject_Identity)]
  if (n_control < 3L || n_ipf < 3L) return(NULL)
  dt[, disease := factor(Disease_Identity, levels = c("Control", "IPF"))]
  fit <- glm(
    cbind(FASN_expressing_cells, n_cells - FASN_expressing_cells) ~ disease,
    family = quasibinomial(), data = dt
  )
  coefficient_name <- "diseaseIPF"
  estimate <- coef(fit)[coefficient_name]
  standard_error <- summary(fit)$coefficients[coefficient_name, "Std. Error"]
  critical <- qt(0.975, df = fit$df.residual)
  data.table(
    fine_celltype = dt$fine_celltype[[1]],
    analysis = "Detection prevalence (donor-stratified quasibinomial)",
    effect_scale = "IPF-control log odds",
    n_control = n_control,
    n_ipf = n_ipf,
    IPF_minus_control_effect = unname(estimate),
    CI_low = unname(estimate - critical * standard_error),
    CI_high = unname(estimate + critical * standard_error),
    odds_ratio = unname(exp(estimate)),
    dispersion = summary(fit)$dispersion,
    P = summary(fit)$coefficients[coefficient_name, "Pr(>|t|)"]
  )
}

donor[, detection_logit := qlogis((FASN_expressing_cells + 0.5) / (n_cells + 1))]
donor[, positive_CP10K_log2 := log2(FASN_positive_cell_mean_CP10K + 1e-4)]

analyses <- list()
for (celltype_i in unique(donor$fine_celltype)) {
  dt <- donor[fine_celltype == celltype_i]
  analyses[[paste0(celltype_i, "__quasibinomial")]] <- fit_quasibinomial(dt)
  analyses[[paste0(celltype_i, "__detection_lm")]] <- fit_lm_metric(
    dt, "detection_logit", "Detection prevalence (unweighted empirical-logit sensitivity)",
    "IPF-control empirical logit"
  )
  analyses[[paste0(celltype_i, "__positive")]] <- fit_lm_metric(
    dt[is.finite(positive_CP10K_log2)],
    "positive_CP10K_log2", "Positive-cell normalized abundance",
    "IPF-control log2 mean cell-level CP10K"
  )
}
hurdle <- rbindlist(analyses, fill = TRUE)
hurdle[, BH_FDR := p.adjust(P, method = "BH"), by = analysis]
fwrite(hurdle, file.path(input_dir, "GSE136831_FASN_hurdle_style_sensitivity.csv"))

focus <- c("Ciliated", "Alveolar macrophage", "Non-alveolar macrophage")
plot_donor <- donor[fine_celltype %in% focus]
plot_donor[, fine_celltype := factor(fine_celltype, levels = focus)]
colors <- c(Control = "#0072B2", IPF = "#D55E00")

p_detection <- ggplot(plot_donor, aes(Disease_Identity, 100 * FASN_detection_rate, color = Disease_Identity)) +
  geom_boxplot(outlier.shape = NA, width = 0.55, linewidth = 0.45) +
  geom_jitter(width = 0.13, height = 0, size = 1.25, alpha = 0.72) +
  facet_wrap(~ fine_celltype, scales = "free_y") +
  scale_color_manual(values = colors) +
  labs(x = NULL, y = "FASN-positive cells (%)", title = "A  Donor-level detection prevalence") +
  theme_classic(base_size = 9) +
  theme(legend.position = "none", strip.background = element_blank(), strip.text = element_text(face = "bold"),
        plot.title = element_text(face = "bold"))

p_positive <- ggplot(
  plot_donor[is.finite(positive_CP10K_log2)],
  aes(Disease_Identity, positive_CP10K_log2, color = Disease_Identity)
) +
  geom_boxplot(outlier.shape = NA, width = 0.55, linewidth = 0.45) +
  geom_jitter(width = 0.13, height = 0, size = 1.25, alpha = 0.72) +
  facet_wrap(~ fine_celltype, scales = "free_y") +
  scale_color_manual(values = colors) +
  labs(x = NULL, y = "Positive-cell mean FASN CP10K (log2)",
       title = "B  Positive-cell normalized abundance") +
  theme_classic(base_size = 9) +
  theme(legend.position = "none", strip.background = element_blank(), strip.text = element_text(face = "bold"),
        plot.title = element_text(face = "bold"))

p_hurdle <- p_detection / p_positive
ggsave(file.path(fig_dir, "Figure_S7_FASN_low_abundance_hurdle_sensitivity.pdf"), p_hurdle, width = 7.1, height = 6.6, units = "in")
ggsave(file.path(fig_dir, "Figure_S7_FASN_low_abundance_hurdle_sensitivity.png"), p_hurdle, width = 7.1, height = 6.6, units = "in", dpi = 300)
ggsave(file.path(fig_dir, "Figure_S7_FASN_low_abundance_hurdle_sensitivity.tiff"), p_hurdle, width = 7.1, height = 6.6, units = "in", dpi = 600, compression = "lzw")

mds_focus <- mds[fine_celltype %in% focus]
mds_focus[, fine_celltype := factor(fine_celltype, levels = focus)]
p_mds <- ggplot(
  mds_focus,
  aes(MDS1, MDS2, color = Disease_Identity, shape = library_replication)
) +
  geom_point(size = 2.2, alpha = 0.82) +
  facet_wrap(~ fine_celltype, scales = "free") +
  scale_color_manual(values = colors) +
  scale_shape_manual(values = c("Single library" = 16, "Multiple libraries" = 17)) +
  labs(
    x = "Leading log-fold-change dimension 1", y = "Leading log-fold-change dimension 2",
    color = "Disease", shape = "Donor library status",
    title = "Primary-threshold donor pseudobulk MDS"
  ) +
  theme_classic(base_size = 9) +
  theme(strip.background = element_blank(), strip.text = element_text(face = "bold"),
        plot.title = element_text(face = "bold"), legend.position = "bottom")
ggsave(file.path(fig_dir, "Figure_S8_GSE136831_pseudobulk_MDS.pdf"), p_mds, width = 7.1, height = 3.7, units = "in")
ggsave(file.path(fig_dir, "Figure_S8_GSE136831_pseudobulk_MDS.png"), p_mds, width = 7.1, height = 3.7, units = "in", dpi = 300)
ggsave(file.path(fig_dir, "Figure_S8_GSE136831_pseudobulk_MDS.tiff"), p_mds, width = 7.1, height = 3.7, units = "in", dpi = 600, compression = "lzw")

message("Single-cell confounding and low-abundance sensitivities completed")
