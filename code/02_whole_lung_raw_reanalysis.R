suppressPackageStartupMessages({
  library(data.table)
  library(edgeR)
  library(limma)
  library(metafor)
  library(openxlsx)
  library(oligo)
  library(affy)
  library(Biobase)
  library(ggplot2)
  library(patchwork)
})

set.seed(20260710)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript 02_whole_lung_raw_reanalysis.R <raw-data-root> <analysis-root>")
}
raw_data_dir <- normalizePath(args[[1]], mustWork = TRUE)
analysis_dir <- normalizePath(args[[2]], mustWork = TRUE)
out_dir <- file.path(analysis_dir, "results", "whole_lung")
fig_dir <- file.path(analysis_dir, "figures", "supplementary")
matrix_dir <- file.path(analysis_dir, "derived_matrices")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(matrix_dir, recursive = TRUE, showWarnings = FALSE)

clean_symbol <- function(x) {
  x <- as.character(x)
  x <- sub("\\s*///.*$", "", x)
  x <- sub("\\s*//.*$", "", x)
  x <- trimws(x)
  x[x %in% c("", "---", "NA", "na", "NULL")] <- NA_character_
  toupper(x)
}

read_geo_series_matrix <- function(path) {
  lines <- readLines(gzfile(path), warn = FALSE)
  begin <- grep("^!series_matrix_table_begin", lines)[1]
  end <- grep("^!series_matrix_table_end", lines)[1]
  if (is.na(begin) || is.na(end)) stop("Expression table not found: ", path)
  expr_dt <- fread(text = paste(lines[(begin + 1):(end - 1)], collapse = "\n"), data.table = FALSE)
  ids <- as.character(expr_dt[[1]])
  expr <- data.matrix(expr_dt[, -1, drop = FALSE])
  rownames(expr) <- ids
  colnames(expr) <- names(expr_dt)[-1]
  sample_lines <- lines[seq_len(begin - 1)]
  sample_lines <- sample_lines[grepl("^!Sample_", sample_lines)]
  meta_list <- list()
  for (line in sample_lines) {
    parts <- strsplit(line, "\t", fixed = TRUE)[[1]]
    values <- gsub('^"|"$', "", parts[-1])
    if (length(values) != ncol(expr)) next
    key <- sub("^!", "", parts[1])
    name <- key
    k <- 2
    while (name %in% names(meta_list)) {
      name <- paste0(key, "_", k)
      k <- k + 1
    }
    meta_list[[name]] <- values
  }
  meta <- as.data.frame(meta_list, stringsAsFactors = FALSE, check.names = FALSE)
  rownames(meta) <- colnames(expr)
  list(expr = expr, meta = meta)
}

extract_characteristic <- function(meta, field) {
  values <- rep(NA_character_, nrow(meta))
  cols <- names(meta)[grepl("^Sample_characteristics", names(meta))]
  for (col in cols) {
    x <- meta[[col]]
    hit <- grepl(paste0("^", field, "\\s*:"), x, ignore.case = TRUE)
    idx <- which(hit & is.na(values))
    if (length(idx) > 0) values[idx] <- trimws(sub("^[^:]+:\\s*", "", x[idx]))
  }
  values
}

read_platform_annotation <- function(path) {
  lines <- readLines(gzfile(path), warn = FALSE)
  header <- grep("^ID\t", lines)[1]
  if (is.na(header)) stop("Annotation header not found: ", path)
  annot <- fread(
    text = paste(lines[header:length(lines)], collapse = "\n"),
    sep = "\t", quote = "", select = c("ID", "Gene symbol"),
    data.table = FALSE, fill = TRUE
  )
  names(annot) <- c("ID", "symbol")
  annot$ID <- as.character(annot$ID)
  annot$symbol <- clean_symbol(annot$symbol)
  annot <- annot[!is.na(annot$symbol), , drop = FALSE]
  annot[!duplicated(annot$ID), , drop = FALSE]
}

collapse_to_gene <- function(expr, annot) {
  idx <- match(rownames(expr), annot$ID)
  symbol <- annot$symbol[idx]
  keep <- !is.na(symbol)
  expr <- expr[keep, , drop = FALSE]
  symbol <- symbol[keep]
  probe_iqr <- apply(expr, 1, IQR, na.rm = TRUE)
  ord <- order(symbol, -probe_iqr)
  first <- !duplicated(symbol[ord])
  out <- expr[ord[first], , drop = FALSE]
  rownames(out) <- symbol[ord[first]]
  out
}

run_limma <- function(expr, group, dataset) {
  group <- factor(group[colnames(expr)], levels = c("Control", "IPF"))
  keep <- !is.na(group)
  expr <- expr[, keep, drop = FALSE]
  group <- droplevels(group[keep])
  design <- model.matrix(~ 0 + group)
  colnames(design) <- levels(group)
  fit <- lmFit(expr, design)
  fit <- contrasts.fit(fit, makeContrasts(IPF - Control, levels = design))
  fit <- eBayes(fit, robust = TRUE)
  tt <- topTable(fit, number = Inf, sort.by = "none")
  tt$gene <- rownames(tt)
  tt$dataset <- dataset
  tt$AveExpr <- rowMeans(expr, na.rm = TRUE)
  tt[, c("dataset", "gene", "logFC", "AveExpr", "t", "P.Value", "adj.P.Val", "B")]
}

run_voom <- function(count_mat, group, dataset) {
  group <- factor(group[colnames(count_mat)], levels = c("Control", "IPF"))
  keep_samples <- !is.na(group)
  count_mat <- count_mat[, keep_samples, drop = FALSE]
  group <- droplevels(group[keep_samples])
  y <- DGEList(counts = count_mat, group = group)
  keep <- filterByExpr(y, group = group)
  y <- y[keep, , keep.lib.sizes = FALSE]
  y <- calcNormFactors(y)
  design <- model.matrix(~ 0 + group)
  colnames(design) <- levels(group)
  v <- voom(y, design, plot = FALSE)
  fit <- lmFit(v, design)
  fit <- contrasts.fit(fit, makeContrasts(IPF - Control, levels = design))
  fit <- eBayes(fit, robust = TRUE)
  tt <- topTable(fit, number = Inf, sort.by = "none")
  tt$gene <- rownames(tt)
  tt$dataset <- dataset
  tt$AveExpr <- rowMeans(v$E, na.rm = TRUE)
  list(
    stats = tt[, c("dataset", "gene", "logFC", "AveExpr", "t", "P.Value", "adj.P.Val", "B")],
    expression = v$E,
    group = setNames(as.character(group), colnames(v$E))
  )
}

hedges_g <- function(x_ipf, x_control) {
  x_ipf <- as.numeric(x_ipf[is.finite(x_ipf)])
  x_control <- as.numeric(x_control[is.finite(x_control)])
  n1 <- length(x_ipf)
  n0 <- length(x_control)
  if (n1 < 2 || n0 < 2) return(c(g = NA, variance = NA, n_ipf = n1, n_control = n0))
  df <- n1 + n0 - 2
  sp2 <- ((n1 - 1) * var(x_ipf) + (n0 - 1) * var(x_control)) / df
  if (!is.finite(sp2) || sp2 <= 0) return(c(g = NA, variance = NA, n_ipf = n1, n_control = n0))
  d <- (mean(x_ipf) - mean(x_control)) / sqrt(sp2)
  J <- 1 - 3 / (4 * df - 1)
  g <- J * d
  variance <- (n1 + n0) / (n1 * n0) + g^2 / (2 * df)
  c(g = g, variance = variance, n_ipf = n1, n_control = n0)
}

cohort_effects <- function(expr, group, genes, dataset, source) {
  common <- intersect(genes, rownames(expr))
  rows <- lapply(common, function(gene) {
    eff <- hedges_g(expr[gene, group == "IPF"], expr[gene, group == "Control"])
    data.frame(
      dataset = dataset,
      source = source,
      gene = gene,
      n_control = eff[["n_control"]],
      n_ipf = eff[["n_ipf"]],
      hedges_g = eff[["g"]],
      variance = eff[["variance"]],
      SE = sqrt(eff[["variance"]]),
      ci_low = eff[["g"]] - 1.96 * sqrt(eff[["variance"]]),
      ci_high = eff[["g"]] + 1.96 * sqrt(eff[["variance"]]),
      stringsAsFactors = FALSE
    )
  })
  rbindlist(rows, fill = TRUE)
}

meta_candidates <- function(effect_table) {
  rows <- list()
  for (gene_i in unique(effect_table$gene)) {
    x <- effect_table[effect_table$gene == gene_i & is.finite(effect_table$hedges_g) &
                        is.finite(effect_table$variance) & effect_table$variance > 0]
    if (nrow(x) < 2) next
    fit <- tryCatch(metafor::rma(yi = x$hedges_g, vi = x$variance, method = "REML", test = "knha"), error = function(e) NULL)
    if (is.null(fit)) next
    pred <- tryCatch(predict(fit), error = function(e) NULL)
    rows[[length(rows) + 1]] <- data.frame(
      gene = gene_i,
      k = nrow(x),
      meta_hedges_g = as.numeric(fit$b[1]),
      meta_SE = fit$se,
      meta_p = fit$pval,
      meta_CI_low = fit$ci.lb,
      meta_CI_high = fit$ci.ub,
      prediction_low = if (is.null(pred)) NA_real_ else pred$pi.lb,
      prediction_high = if (is.null(pred)) NA_real_ else pred$pi.ub,
      tau2 = fit$tau2,
      I2 = fit$I2,
      datasets = paste(x$dataset, collapse = ";"),
      stringsAsFactors = FALSE
    )
  }
  out <- rbindlist(rows, fill = TRUE)
  out[order(meta_p)]
}

make_bins <- function(values, nbin = 10) {
  q <- unique(quantile(values[is.finite(values)], probs = seq(0, 1, length.out = nbin + 1), na.rm = TRUE))
  if (length(q) < 3) return(rep(1L, length(values)))
  as.integer(cut(values, breaks = q, include.lowest = TRUE, labels = FALSE))
}

matched_background <- function(stats, candidate_genes, dataset, B = 5000) {
  stats <- stats[is.finite(stats$P.Value) & is.finite(stats$AveExpr), ]
  candidates <- intersect(candidate_genes, stats$gene)
  stats$bin <- make_bins(stats$AveExpr)
  candidate_bins <- stats$bin[match(candidates, stats$gene)]
  background <- stats[!(stats$gene %in% candidates), ]
  candidate_p <- stats$P.Value[match(candidates, stats$gene)]
  observed <- sum(p.adjust(candidate_p, method = "BH") < 0.10, na.rm = TRUE)
  null <- numeric(B)
  for (b in seq_len(B)) {
    sampled <- character()
    for (bin in unique(na.omit(candidate_bins))) {
      n <- sum(candidate_bins == bin, na.rm = TRUE)
      pool <- background$gene[background$bin == bin]
      if (length(pool) == 0) pool <- background$gene
      sampled <- c(sampled, sample(pool, n, replace = length(pool) < n))
    }
    sampled <- sampled[seq_len(min(length(sampled), length(candidates)))]
    p <- stats$P.Value[match(sampled, stats$gene)]
    null[b] <- sum(p.adjust(p, method = "BH") < 0.10, na.rm = TRUE)
  }
  list(
    summary = data.frame(
      dataset = dataset,
      measured_candidates = length(candidates),
      observed_FDR10 = observed,
      null_mean = mean(null),
      null_q025 = unname(quantile(null, 0.025)),
      null_q975 = unname(quantile(null, 0.975)),
      empirical_p = (sum(null >= observed) + 1) / (B + 1),
      B = B
    ),
    null = data.frame(dataset = dataset, iteration = seq_len(B), null_FDR10 = null)
  )
}

# Prepare FASN source effects; selection is finalized after transcriptome-wide calibration in 02b/02c.
candidates <- "FASN"

# GSE150910 raw gene-level counts.
count_df <- fread(file.path(raw_data_dir, "GSE150910", "GSE150910_gene-level_count_file.csv.gz"), data.table = FALSE)
count_df$symbol <- clean_symbol(count_df$symbol)
count_df <- count_df[!is.na(count_df$symbol), , drop = FALSE]
count_mat <- data.matrix(count_df[, setdiff(names(count_df), "symbol"), drop = FALSE])
rownames(count_mat) <- count_df$symbol
count_mat <- rowsum(count_mat, group = rownames(count_mat), reorder = FALSE)
group150 <- ifelse(grepl("^ipf_", colnames(count_mat), ignore.case = TRUE), "IPF",
                   ifelse(grepl("^control_", colnames(count_mat), ignore.case = TRUE), "Control", NA))
names(group150) <- colnames(count_mat)
fit150 <- run_voom(count_mat, group150, "GSE150910")
expr150 <- fit150$expression
group150 <- fit150$group

# GSE110147 raw CEL files, RMA normalized with oligo at the core transcript level.
g110_series <- read_geo_series_matrix(file.path(raw_data_dir, "GSE110147", "GSE110147_series_matrix.txt.gz"))
disease110 <- extract_characteristic(g110_series$meta, "disease state")
group110_meta <- ifelse(grepl("Idiopathic pulmonary fibrosis", disease110, ignore.case = TRUE), "IPF",
                        ifelse(grepl("Normal control", disease110, ignore.case = TRUE), "Control", NA))
names(group110_meta) <- rownames(g110_series$meta)
annot6244 <- read_platform_annotation(file.path(raw_data_dir, "platforms", "GPL6244.annot.gz"))
rds110 <- file.path(matrix_dir, "GSE110147_rawCEL_RMA_gene.rds")
cel110 <- list.files(file.path(raw_data_dir, "GSE110147"), pattern = "CEL.gz$", full.names = TRUE,
                     ignore.case = TRUE, recursive = TRUE)
if (length(cel110) > 0L) {
  raw110 <- oligo::read.celfiles(cel110, verbose = FALSE)
  rma110 <- oligo::rma(raw110, target = "core", background = TRUE, normalize = TRUE)
  expr110_probe <- Biobase::exprs(rma110)
  gsm110 <- sub("_.*$", "", basename(colnames(expr110_probe)))
  colnames(expr110_probe) <- gsm110
  expr110 <- collapse_to_gene(expr110_probe, annot6244)
  group110 <- group110_meta[colnames(expr110)]
} else if (file.exists(rds110)) {
  obj110 <- readRDS(rds110)
  expr110 <- obj110$expression
  group110 <- obj110$group
} else {
  stop("No GSE110147 CEL files found under raw-data-root and no cached RDS is available")
}
fit110 <- run_limma(expr110, group110, "GSE110147")

# GSE24206 raw CEL files, RMA normalized with affy.
g242_series <- read_geo_series_matrix(file.path(raw_data_dir, "GSE24206", "GSE24206_series_matrix.txt.gz"))
phenotype242 <- extract_characteristic(g242_series$meta, "phenotype")
group242_meta <- ifelse(grepl("idiopathic pulmonary fibrosis|IPF", phenotype242, ignore.case = TRUE), "IPF",
                        ifelse(grepl("healthy", phenotype242, ignore.case = TRUE), "Control", NA))
names(group242_meta) <- rownames(g242_series$meta)
annot570 <- read_platform_annotation(file.path(raw_data_dir, "platforms", "GPL570.annot.gz"))
rds242 <- file.path(matrix_dir, "GSE24206_rawCEL_RMA_gene.rds")
cel242 <- list.files(file.path(raw_data_dir, "GSE24206"), pattern = "CEL.gz$", full.names = TRUE,
                     ignore.case = TRUE, recursive = TRUE)
if (length(cel242) > 0L) {
  raw242 <- affy::ReadAffy(filenames = cel242, verbose = FALSE)
  rma242 <- affy::rma(raw242, background = TRUE, normalize = TRUE, verbose = FALSE)
  expr242_probe <- Biobase::exprs(rma242)
  gsm242 <- sub("\\.CEL\\.gz$", "", basename(colnames(expr242_probe)), ignore.case = TRUE)
  colnames(expr242_probe) <- gsm242
  expr242 <- collapse_to_gene(expr242_probe, annot570)
  group242 <- group242_meta[colnames(expr242)]
} else if (file.exists(rds242)) {
  obj242 <- readRDS(rds242)
  expr242 <- obj242$expression
  group242 <- obj242$group
} else {
  stop("No GSE24206 CEL files found under raw-data-root and no cached RDS is available")
}
fit242 <- run_limma(expr242, group242, "GSE24206")

saveRDS(list(expression = expr150, group = group150), file.path(matrix_dir, "GSE150910_logCPM.rds"))
saveRDS(list(expression = expr110, group = group110), file.path(matrix_dir, "GSE110147_rawCEL_RMA_gene.rds"))
saveRDS(list(expression = expr242, group = group242), file.path(matrix_dir, "GSE24206_rawCEL_RMA_gene.rds"))

write.csv(fit150$stats, file.path(out_dir, "GSE150910_raw_counts_all_gene_limma_voom.csv"), row.names = FALSE)
write.csv(fit110, file.path(out_dir, "GSE110147_raw_CEL_RMA_all_gene_limma.csv"), row.names = FALSE)
write.csv(fit242, file.path(out_dir, "GSE24206_raw_CEL_RMA_all_gene_limma.csv"), row.names = FALSE)

effects <- rbindlist(list(
  cohort_effects(expr150, group150, candidates, "GSE150910", "raw gene counts"),
  cohort_effects(expr110, group110, candidates, "GSE110147", "raw CEL RMA"),
  cohort_effects(expr242, group242, candidates, "GSE24206", "raw CEL RMA")
), fill = TRUE)
meta <- meta_candidates(effects)
write.csv(effects, file.path(out_dir, "whole_lung_candidate_Hedges_g_from_source_data.csv"), row.names = FALSE)
write.csv(meta, file.path(out_dir, "whole_lung_candidate_meta_HK_from_source_data.csv"), row.names = FALSE)

fasn_effects <- effects[gene == "FASN"]
fasn_meta <- meta[gene == "FASN"]
write.csv(fasn_effects, file.path(out_dir, "FASN_cohort_effects_from_source_data.csv"), row.names = FALSE)
write.csv(fasn_meta, file.path(out_dir, "FASN_meta_HK_prediction_interval.csv"), row.names = FALSE)

loo_rows <- list()
for (omit in fasn_effects$dataset) {
  x <- fasn_effects[dataset != omit & is.finite(hedges_g) & is.finite(variance)]
  fit <- tryCatch(metafor::rma(yi = x$hedges_g, vi = x$variance, method = "REML", test = "knha"), error = function(e) NULL)
  if (is.null(fit)) next
  pred <- tryCatch(predict(fit), error = function(e) NULL)
  loo_rows[[length(loo_rows) + 1]] <- data.frame(
    omitted_cohort = omit,
    k = nrow(x),
    pooled_g = as.numeric(fit$b[1]),
    CI_low = fit$ci.lb,
    CI_high = fit$ci.ub,
    p_value = fit$pval,
    I2 = fit$I2,
    prediction_low = if (is.null(pred)) NA_real_ else pred$pi.lb,
    prediction_high = if (is.null(pred)) NA_real_ else pred$pi.ub
  )
}
fasn_loo <- rbindlist(loo_rows, fill = TRUE)
write.csv(fasn_loo, file.path(out_dir, "FASN_leave_one_cohort_out_HK.csv"), row.names = FALSE)

# Processed series matrices are retained only as a preprocessing sensitivity check.
expr110_series <- collapse_to_gene(g110_series$expr, annot6244)
expr242_series <- collapse_to_gene(g242_series$expr, annot570)
series_effects <- rbindlist(list(
  cohort_effects(expr110_series, group110_meta[colnames(expr110_series)], "FASN", "GSE110147", "GEO series matrix"),
  cohort_effects(expr242_series, group242_meta[colnames(expr242_series)], "FASN", "GSE24206", "GEO series matrix")
), fill = TRUE)
write.csv(series_effects, file.path(out_dir, "FASN_raw_CEL_vs_series_matrix_sensitivity.csv"), row.names = FALSE)

stats_list <- list(GSE150910 = fit150$stats, GSE110147 = fit110, GSE24206 = fit242)
bg <- lapply(names(stats_list), function(ds) matched_background(stats_list[[ds]], candidates, ds, B = 5000))
bg_summary <- rbindlist(lapply(bg, `[[`, "summary"), fill = TRUE)
bg_null <- rbindlist(lapply(bg, `[[`, "null"), fill = TRUE)
write.csv(bg_summary, file.path(out_dir, "whole_lung_matched_background_summary_source_data.csv"), row.names = FALSE)
write.csv(bg_null, file.path(out_dir, "whole_lung_matched_background_null_source_data.csv"), row.names = FALSE)

sample_manifest <- rbindlist(list(
  data.frame(dataset = "GSE150910", sample = names(group150), group = unname(group150), source = "raw gene-level counts"),
  data.frame(dataset = "GSE110147", sample = names(group110), group = unname(group110), source = "raw CEL, RMA"),
  data.frame(dataset = "GSE24206", sample = names(group242), group = unname(group242), source = "raw CEL, RMA")
), fill = TRUE)
write.csv(sample_manifest, file.path(out_dir, "whole_lung_sample_manifest_source_data.csv"), row.names = FALSE)

p_null <- ggplot(bg_null, aes(null_FDR10)) +
  geom_histogram(binwidth = 2, fill = "#BDBDBD", color = "white", boundary = 0) +
  geom_vline(data = bg_summary, aes(xintercept = observed_FDR10), color = "#D55E00", linewidth = 0.8) +
  facet_wrap(~ dataset, scales = "free_y", nrow = 1) +
  labs(x = "Matched-background genes with candidate-set FDR < 0.10", y = "Permutation count",
       title = "Matched-background calibration from source-level reanalysis") +
  theme_classic(base_size = 9) +
  theme(plot.title = element_text(face = "bold"), strip.background = element_blank())
ggsave(file.path(fig_dir, "Figure_S3_matched_background_null.pdf"), p_null, width = 7.1, height = 3.1, units = "in")
ggsave(file.path(fig_dir, "Figure_S3_matched_background_null.png"), p_null, width = 7.1, height = 3.1, units = "in", dpi = 300)
ggsave(file.path(fig_dir, "Figure_S3_matched_background_null.tiff"), p_null, width = 7.1, height = 3.1, units = "in", dpi = 600, compression = "lzw")

message("Whole-lung source-level reanalysis completed: ", normalizePath(out_dir))
