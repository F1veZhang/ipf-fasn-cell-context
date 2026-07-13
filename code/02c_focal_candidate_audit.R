suppressPackageStartupMessages({
  library(data.table)
  library(AnnotationDbi)
  library(org.Hs.eg.db)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript 02c_focal_candidate_audit.R <analysis-root>")
}
analysis_dir <- normalizePath(args[[1]], mustWork = TRUE)
at2_dir <- file.path(analysis_dir, "results", "AT2")
whole_lung_dir <- file.path(analysis_dir, "results", "whole_lung")

at2 <- fread(file.path(at2_dir, "GSE245965_AT2_raw_count_voom_all_genes.csv"))
gsea <- fread(file.path(at2_dir, "GSE245965_AT2_GSEA_full.csv"))
meta <- fread(file.path(whole_lung_dir, "whole_lung_transcriptome_meta_HK_from_source_data.csv.gz"))

leading_edge <- function(pathway_name) {
  value <- gsea[pathway == pathway_name, leadingEdge]
  if (length(value) != 1L) stop("Expected one GSEA row for ", pathway_name)
  unique(strsplit(value, ";", fixed = TRUE)[[1]])
}

hallmark_ids <- leading_edge("HALLMARK_FATTY_ACID_METABOLISM")
reactome_ids <- leading_edge("REACTOME_FATTY_ACID_METABOLISM")
eligible_ids <- intersect(hallmark_ids, reactome_ids)

at2[, ENTREZID := as.character(gene_id)]
at2[, symbol := mapIds(
  org.Hs.eg.db, keys = ENTREZID, keytype = "ENTREZID", column = "SYMBOL",
  multiVals = "first"
)]

candidates <- at2[
  ENTREZID %in% eligible_ids & adj.P.Val < 0.05 & logFC < -1 & !is.na(symbol),
  .(
    gene = symbol,
    ENTREZID,
    AT2_log2FC = logFC,
    AT2_P = P.Value,
    AT2_FDR = adj.P.Val,
    Hallmark_fatty_acid_leading_edge = TRUE,
    Reactome_fatty_acid_leading_edge = TRUE
  )
]
candidates <- merge(
  candidates,
  meta[, .(
    gene, measured_in_three_cohorts = k == 3L, whole_lung_meta_g = meta_hedges_g,
    whole_lung_meta_P = meta_p, whole_lung_meta_FDR = meta_FDR,
    whole_lung_meta_rank = p_rank
  )],
  by = "gene", all.x = TRUE
)
candidates <- candidates[measured_in_three_cohorts == TRUE]
setorder(candidates, whole_lung_meta_P)
candidates[, focal_rank_among_rule_positive_genes := seq_len(.N)]
candidates[, focal_interpretation := fifelse(
  gene == "FASN",
  "Focal contextual case: smallest nominal whole-lung meta-analysis P among rule-positive genes and direct role in de novo fatty-acid synthesis",
  "Rule-positive gene reported for selection transparency"
)]

if (!identical(sort(candidates$gene), sort(c("ACADL", "HSD17B4", "ACSL1", "FASN", "ACSM3", "ACSL4")))) {
  stop("Focal-rule reconstruction did not produce the expected six-gene set")
}

fwrite(candidates, file.path(whole_lung_dir, "genes_meeting_focal_selection_criteria.csv"))
message("Focal-selection audit completed: ", nrow(candidates), " genes met all criteria")
