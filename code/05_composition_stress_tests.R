suppressPackageStartupMessages({
  library(data.table)
  library(nnls)
  library(car)
  library(ggplot2)
  library(patchwork)
})

set.seed(20260710)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript 05_composition_stress_tests.R <analysis-root>")
}
analysis_dir <- normalizePath(args[[1]], mustWork = TRUE)
sc_dir <- file.path(analysis_dir, "results", "lung_scrna")
matrix_dir <- file.path(analysis_dir, "derived_matrices")
out_dir <- file.path(analysis_dir, "results", "composition")
fig_dir <- file.path(analysis_dir, "figures", "supplementary")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

deconv_celltypes <- c(
  "AT2", "AT1", "Aberrant basaloid", "Fibroblast", "Myofibroblast",
  "Macrophage", "Monocyte", "Endothelial", "T/NK", "B/plasma"
)
core_covariates <- c("AT2", "AT1", "Fibroblast", "Myofibroblast", "Macrophage", "Endothelial")

safe_name <- function(x) gsub("[^A-Za-z0-9]+", "_", x)

scale_01 <- function(x) {
  rng <- range(x, finite = TRUE, na.rm = TRUE)
  if (!all(is.finite(rng)) || diff(rng) < 1e-8) return(rep(0, length(x)))
  pmax(0, pmin(1, (x - rng[1]) / diff(rng)))
}

marker_ref <- fread(file.path(sc_dir, "GSE136831_marker_reference_from_raw_counts.csv"))
signature_dt <- dcast(marker_ref, gene ~ major_celltype, value.var = "avg_cp10k", fun.aggregate = mean, fill = 0)
signature_cols <- intersect(deconv_celltypes, names(signature_dt))
signature <- as.matrix(signature_dt[, ..signature_cols])
rownames(signature) <- signature_dt$gene
signature <- log1p(signature)
signature <- t(apply(signature, 1, scale_01))
colnames(signature) <- signature_cols
signature <- signature[rowSums(signature) > 0, , drop = FALSE]
write.csv(as.data.table(signature, keep.rownames = "gene"), file.path(out_dir, "GSE136831_raw_marker_signature.csv"), row.names = FALSE)

fit_group_model <- function(df, covariates = character()) {
  df$group <- factor(df$group, levels = c("Control", "IPF"))
  terms <- c("group", covariates)
  formula <- as.formula(paste("FASN_z ~", paste(terms, collapse = " + ")))
  lm(formula, data = df)
}

extract_model <- function(fit, dataset, model, covariates, condition_number = NA_real_) {
  co <- summary(fit)$coefficients
  ci <- confint(fit)
  data.table(
    dataset = dataset,
    model = model,
    estimate = unname(co["groupIPF", "Estimate"]),
    SE = unname(co["groupIPF", "Std. Error"]),
    statistic = unname(co["groupIPF", "t value"]),
    p_value = unname(co["groupIPF", "Pr(>|t|)"]),
    conf_low = unname(ci["groupIPF", 1]),
    conf_high = unname(ci["groupIPF", 2]),
    n_samples = nobs(fit),
    covariates = paste(covariates, collapse = ";"),
    signature_condition_number = condition_number
  )
}

estimate_props <- function(expr, signature_matrix) {
  common <- intersect(rownames(signature_matrix), rownames(expr))
  if (length(common) < 8) stop("Too few common marker genes")
  S <- signature_matrix[common, , drop = FALSE]
  B <- expr[common, , drop = FALSE]
  B <- t(apply(B, 1, scale_01))
  rownames(B) <- common
  colnames(B) <- colnames(expr)
  S[!is.finite(S)] <- 0
  B[!is.finite(B)] <- 0
  props <- matrix(0, nrow = ncol(B), ncol = ncol(S), dimnames = list(colnames(B), colnames(S)))
  residual <- numeric(ncol(B))
  for (j in seq_len(ncol(B))) {
    fit <- nnls(S, B[, j])
    co <- pmax(coef(fit), 0)
    if (sum(co) > 0) co <- co / sum(co)
    props[j, ] <- co
    residual[j] <- sqrt(mean((as.numeric(S %*% co) - B[, j])^2))
  }
  list(
    proportions = props,
    residual = residual,
    common_genes = common,
    condition_number = kappa(S, exact = TRUE)
  )
}

marker_scores <- function(expr, marker_ref_table) {
  intended <- unique(marker_ref_table[, .(marker_celltype, gene)])
  intended <- intended[marker_celltype %in% deconv_celltypes & gene %in% rownames(expr)]
  out <- matrix(NA_real_, nrow = ncol(expr), ncol = length(unique(intended$marker_celltype)))
  rownames(out) <- colnames(expr)
  colnames(out) <- unique(intended$marker_celltype)
  for (ct in colnames(out)) {
    genes <- intended[marker_celltype == ct, unique(gene)]
    z <- t(scale(t(expr[genes, , drop = FALSE])))
    z[!is.finite(z)] <- 0
    out[, ct] <- colMeans(z)
  }
  out
}

make_model_df <- function(expr, group, props) {
  sample_names <- intersect(colnames(expr), rownames(props))
  df <- as.data.frame(props[sample_names, , drop = FALSE], check.names = FALSE)
  df$sample <- sample_names
  df$group <- unname(group[sample_names])
  df$FASN_z <- as.numeric(scale(as.numeric(expr["FASN", sample_names])))
  for (ct in colnames(props)) {
    name <- paste0("prop_", safe_name(ct), "_z")
    df[[name]] <- as.numeric(scale(df[[ct]]))
  }
  df
}

bootstrap_coefficient <- function(df, covariates, B = 1000) {
  controls <- which(df$group == "Control")
  cases <- which(df$group == "IPF")
  estimates <- rep(NA_real_, B)
  for (b in seq_len(B)) {
    idx <- c(sample(controls, length(controls), replace = TRUE), sample(cases, length(cases), replace = TRUE))
    boot <- df[idx, , drop = FALSE]
    fit <- tryCatch(fit_group_model(boot, covariates), error = function(e) NULL)
    if (!is.null(fit) && "groupIPF" %in% names(coef(fit))) estimates[b] <- coef(fit)[["groupIPF"]]
  }
  valid <- estimates[is.finite(estimates)]
  c(
    low = if (length(valid) < 0.8 * B) NA_real_ else unname(quantile(valid, 0.025)),
    high = if (length(valid) < 0.8 * B) NA_real_ else unname(quantile(valid, 0.975)),
    valid = length(valid)
  )
}

run_dataset <- function(object, dataset) {
  expr <- object$expression
  group <- object$group[colnames(expr)]
  keep <- !is.na(group)
  expr <- expr[, keep, drop = FALSE]
  group <- group[keep]

  deconv <- estimate_props(expr, signature)
  df <- make_model_df(expr, group, deconv$proportions)
  unadjusted <- fit_group_model(df)

  core <- paste0("prop_", safe_name(core_covariates), "_z")
  core <- core[core %in% names(df) & vapply(df[core], function(x) sd(x, na.rm = TRUE) > 1e-8, logical(1))]
  adjusted <- fit_group_model(df, core)

  scores <- marker_scores(expr, marker_ref)
  score_df <- data.frame(
    FASN_z = as.numeric(scale(as.numeric(expr["FASN", rownames(scores)]))),
    group = unname(group[rownames(scores)]),
    scores,
    check.names = FALSE
  )
  score_covars <- intersect(core_covariates, colnames(scores))
  score_covars <- score_covars[vapply(score_df[score_covars], function(x) sd(x, na.rm = TRUE) > 1e-8, logical(1))]
  marker_adjusted <- fit_group_model(score_df, score_covars)

  model_rows <- rbindlist(list(
    extract_model(unadjusted, dataset, "Unadjusted", character(), deconv$condition_number),
    extract_model(marker_adjusted, dataset, "Marker-score adjusted", score_covars, deconv$condition_number),
    extract_model(adjusted, dataset, "NNLS adjusted", core, deconv$condition_number)
  ))

  vif_values <- tryCatch(car::vif(adjusted), error = function(e) numeric())
  vif_dt <- data.table(
    dataset = dataset,
    term = names(vif_values),
    VIF = as.numeric(vif_values),
    signature_condition_number = deconv$condition_number,
    common_signature_genes = length(deconv$common_genes)
  )

  boot <- bootstrap_coefficient(df, core, B = 1000)
  bootstrap_dt <- data.table(
    dataset = dataset,
    model = "NNLS adjusted",
    estimate = coef(adjusted)[["groupIPF"]],
    bootstrap_CI_low = boot[["low"]],
    bootstrap_CI_high = boot[["high"]],
    valid_bootstraps = boot[["valid"]]
  )

  marker_loo <- rbindlist(lapply(deconv$common_genes, function(gene) {
    reduced <- signature[setdiff(rownames(signature), gene), , drop = FALSE]
    ans <- tryCatch(estimate_props(expr, reduced), error = function(e) NULL)
    if (is.null(ans)) return(NULL)
    reduced_df <- make_model_df(expr, group, ans$proportions)
    covars <- core[core %in% names(reduced_df)]
    fit <- tryCatch(fit_group_model(reduced_df, covars), error = function(e) NULL)
    if (is.null(fit)) return(NULL)
    data.table(
      dataset = dataset,
      omitted_marker = gene,
      estimate = coef(fit)[["groupIPF"]],
      p_value = summary(fit)$coefficients["groupIPF", "Pr(>|t|)"],
      condition_number = ans$condition_number
    )
  }), fill = TRUE)

  celltype_loo <- rbindlist(lapply(colnames(signature), function(celltype) {
    reduced <- signature[, setdiff(colnames(signature), celltype), drop = FALSE]
    ans <- tryCatch(estimate_props(expr, reduced), error = function(e) NULL)
    if (is.null(ans)) return(NULL)
    reduced_df <- make_model_df(expr, group, ans$proportions)
    covars <- paste0("prop_", safe_name(setdiff(core_covariates, celltype)), "_z")
    covars <- covars[covars %in% names(reduced_df)]
    fit <- tryCatch(fit_group_model(reduced_df, covars), error = function(e) NULL)
    if (is.null(fit)) return(NULL)
    data.table(
      dataset = dataset,
      omitted_celltype = celltype,
      estimate = coef(fit)[["groupIPF"]],
      p_value = summary(fit)$coefficients["groupIPF", "Pr(>|t|)"],
      condition_number = ans$condition_number
    )
  }), fill = TRUE)

  prop_dt <- as.data.table(deconv$proportions, keep.rownames = "sample")
  prop_dt[, dataset := dataset]
  prop_dt[, group := unname(group[sample])]
  prop_dt[, residual_RMSE := deconv$residual]
  list(
    models = model_rows,
    vif = vif_dt,
    bootstrap = bootstrap_dt,
    marker_loo = marker_loo,
    celltype_loo = celltype_loo,
    proportions = prop_dt
  )
}

objects <- list(
  GSE150910 = readRDS(file.path(matrix_dir, "GSE150910_logCPM.rds")),
  GSE110147 = readRDS(file.path(matrix_dir, "GSE110147_rawCEL_RMA_gene.rds")),
  GSE24206 = readRDS(file.path(matrix_dir, "GSE24206_rawCEL_RMA_gene.rds"))
)
results <- lapply(names(objects), function(dataset) run_dataset(objects[[dataset]], dataset))
names(results) <- names(objects)

models <- rbindlist(lapply(results, `[[`, "models"), fill = TRUE)
vif <- rbindlist(lapply(results, `[[`, "vif"), fill = TRUE)
bootstrap <- rbindlist(lapply(results, `[[`, "bootstrap"), fill = TRUE)
marker_loo <- rbindlist(lapply(results, `[[`, "marker_loo"), fill = TRUE)
celltype_loo <- rbindlist(lapply(results, `[[`, "celltype_loo"), fill = TRUE)
proportions <- rbindlist(lapply(results, `[[`, "proportions"), fill = TRUE)

write.csv(models, file.path(out_dir, "FASN_composition_models_source_reanalysis.csv"), row.names = FALSE)
write.csv(vif, file.path(out_dir, "NNLS_model_VIF_and_condition_number.csv"), row.names = FALSE)
write.csv(bootstrap, file.path(out_dir, "NNLS_FASN_bootstrap_CI.csv"), row.names = FALSE)
write.csv(marker_loo, file.path(out_dir, "NNLS_leave_one_marker_out.csv"), row.names = FALSE)
write.csv(celltype_loo, file.path(out_dir, "NNLS_leave_one_celltype_out.csv"), row.names = FALSE)
write.csv(proportions, file.path(out_dir, "NNLS_proportions_source_reanalysis.csv"), row.names = FALSE)

full_estimate <- models[model == "NNLS adjusted", .(dataset, full_estimate = estimate)]
marker_plot <- merge(marker_loo, full_estimate, by = "dataset")
celltype_plot <- merge(celltype_loo, full_estimate, by = "dataset")
p_loo_marker <- ggplot(marker_plot, aes(estimate)) +
  geom_histogram(bins = 18, fill = "#BDBDBD", color = "white") +
  geom_vline(aes(xintercept = full_estimate), color = "#D55E00", linewidth = 0.8) +
  facet_wrap(~ dataset, scales = "free_y") +
  labs(x = "FASN IPF coefficient", y = "Omitted markers", title = "A  Leave-one-marker-out") +
  theme_classic(base_size = 8.5) +
  theme(plot.title = element_text(face = "bold"), strip.background = element_blank())

p_loo_cell <- ggplot(celltype_plot, aes(dataset, omitted_celltype, fill = estimate)) +
  geom_tile(color = "white", linewidth = 0.35) +
  geom_text(aes(label = sprintf("%.2f", estimate)), size = 2.15) +
  scale_fill_gradient2(low = "#0072B2", mid = "white", high = "#D55E00", midpoint = 0) +
  labs(x = NULL, y = NULL, fill = "IPF coefficient", title = "B  Leave-one-cell-type-out") +
  theme_minimal(base_size = 8.2) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid = element_blank(),
    axis.text.x = element_text(angle = 25, hjust = 1)
  )

p_vif <- ggplot(vif, aes(VIF, reorder(term, VIF), color = dataset)) +
  geom_vline(xintercept = 5, linetype = "dashed", color = "#888888") +
  geom_point(size = 2) +
  scale_color_manual(values = c("#0072B2", "#D55E00", "#009E73")) +
  labs(x = "Variance inflation factor", y = NULL, color = NULL, title = "C  Covariate collinearity") +
  theme_classic(base_size = 8.5) +
  theme(legend.position = "bottom", plot.title = element_text(face = "bold"))

diag_plot <- (p_loo_marker | p_loo_cell) / p_vif
ggsave(file.path(fig_dir, "Figure_S6_deconvolution_stress_tests.pdf"), diag_plot, width = 7.1, height = 6.1, units = "in")
ggsave(file.path(fig_dir, "Figure_S6_deconvolution_stress_tests.png"), diag_plot, width = 7.1, height = 6.1, units = "in", dpi = 300)
ggsave(file.path(fig_dir, "Figure_S6_deconvolution_stress_tests.tiff"), diag_plot, width = 7.1, height = 6.1, units = "in", dpi = 600, compression = "lzw")

message("Composition stress tests completed: ", normalizePath(out_dir))
