# ============================================================
# Script: sanitary_visit_eval_code_summary.r
# Purpose: Summarize sanitary/site visit evaluation-category codes
#          (M/N/R/S/X/Z/D) for the downstream 2SLS sample
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          SDWA_SITE_VISITS.csv
# Outputs: output/sum/sanitary_visit_eval_code_summary.tex
# Author: EK  Date: 2026-07-13
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"
fn <- function(x) format(as.integer(round(x)), big.mark = ",")
fp <- function(x) sprintf("%.1f", x)

# ── 0. Downstream PWSID list ───────────────────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
    col_select = c("PWSID", "year", "minehuc_downstream_of_mine", "minehuc_mine")))
panel <- panel[minehuc_downstream_of_mine == 1 & minehuc_mine == 0]
pws_ids <- unique(panel$PWSID)
cat("Downstream PWSIDs:", length(pws_ids), "\n")

# ── 1. Load site visits, evaluation-code columns ───────────────────────────
eval_cols <- c(
  "MANAGEMENT_OPS_EVAL_CODE", "SOURCE_WATER_EVAL_CODE", "SECURITY_EVAL_CODE",
  "PUMPS_EVAL_CODE", "OTHER_EVAL_CODE", "COMPLIANCE_EVAL_CODE",
  "DATA_VERIFICATION_EVAL_CODE", "TREATMENT_EVAL_CODE",
  "FINISHED_WATER_STOR_EVAL_CODE", "DISTRIBUTION_EVAL_CODE", "FINANCIAL_EVAL_CODE")

sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_ID", "VISIT_DATE", eval_cols),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)

sv[, yr := as.integer(substr(VISIT_DATE, 7, 10))]
sv <- sv[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005]
n_visits <- nrow(sv)
cat("Site visits in downstream sample, 1985-2005:", n_visits, "\n")

# ── 2. Tabulate each evaluation field ──────────────────────────────────────
code_labels <- c(
  M = "Minor deficiencies", N = "No deficiencies or recommendations",
  R = "Recommendations made", S = "Significant deficiencies",
  X = "Not evaluated", Z = "Not applicable", D = "Sanitary defect")
code_order <- names(code_labels)

field_labels <- c(
  MANAGEMENT_OPS_EVAL_CODE = "Management operations",
  SOURCE_WATER_EVAL_CODE = "Source water",
  SECURITY_EVAL_CODE = "Security",
  PUMPS_EVAL_CODE = "Pumps",
  OTHER_EVAL_CODE = "Other facility equipment/management",
  COMPLIANCE_EVAL_CODE = "Compliance",
  DATA_VERIFICATION_EVAL_CODE = "Data verification",
  TREATMENT_EVAL_CODE = "Treatment",
  FINISHED_WATER_STOR_EVAL_CODE = "Finished water storage",
  DISTRIBUTION_EVAL_CODE = "Distribution system",
  FINANCIAL_EVAL_CODE = "Financial")

tab_list <- list()
for (col in eval_cols) {
  counts <- sv[, .N, by = col]
  setnames(counts, col, "code")
  counts[is.na(code), code := "NA"]
  tab_list[[col]] <- counts
}

cat("\nPer-field code distributions:\n")
for (col in eval_cols) {
  cat("\n", field_labels[[col]], ":\n", sep = "")
  print(tab_list[[col]][order(-N)])
}

# ── 3. Build LaTeX table ────────────────────────────────────────────────────
lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Sanitary/Site Visit Evaluation Codes (Downstream 2SLS Sample, 1985--2005)}",
  "\\label{tab:sanitary_visit_eval_code_summary}",
  "\\small",
  "\\begin{tabular}{lrrrrrrrr}",
  "\\hline\\hline",
  " & \\multicolumn{7}{c}{Evaluation code} & \\\\",
  "Evaluation category & M & N & R & S & X & Z & D & N visits \\\\",
  "\\hline"
)

for (col in eval_cols) {
  dt <- tab_list[[col]]
  row_counts <- sapply(code_order, function(cd) {
    v <- dt[code == cd, N]
    if (length(v) == 0) 0L else v
  })
  lines <- c(lines, paste0(
    field_labels[[col]], " & ",
    paste(fn(row_counts), collapse = " & "), " & ",
    fn(n_visits), " \\\\"))
}

lines <- c(lines,
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0("\\textit{Notes:} Sample is the strictly downstream 2SLS sample ",
         "(\\texttt{minehuc\\_downstream\\_of\\_mine}=1, \\texttt{minehuc\\_mine}=0), ",
         "1985--2005 (", fn(length(pws_ids)), " CWSs; ", fn(n_visits), " site visits ",
         "with a valid \\texttt{VISIT\\_DATE} in this window). Codes: M -- Minor ",
         "deficiencies; N -- No deficiencies or recommendations; R -- Recommendations ",
         "made; S -- Significant deficiencies; X -- Not evaluated; Z -- Not applicable; ",
         "D -- Sanitary defect. Cells are counts of site visits by evaluation outcome ",
         "for each of the 11 evaluation categories reported in \\texttt{SDWA\\_SITE\\_VISITS}. ",
         "N visits is the total dated site visits in the sample and is constant across rows; ",
         "row entries need not sum to it because a visit can record any subset of the ",
         "seven codes across categories, and \\texttt{NA} (unreported) values are omitted ",
         "from the M--D columns."),
  "\\end{minipage}",
  "\\end{table}"
)

out_path <- "Z:/ek559/mining_wq/output/sum/sanitary_visit_eval_code_summary.tex"
writeLines(lines, out_path)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
