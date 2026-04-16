# ============================================================
# Script: mr_violation_breakdown.r
# Purpose: Describe what triggers MR violations in SDWA — by violation code,
#          regulatory rule code, and their cross-tab. Restricted to strictly
#          downstream CWSs (minehuc_downstream_of_mine == 1 & minehuc_mine == 0).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet (downstream PWSID filter)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_REF_CODE_VALUES.csv
# Outputs: output/sum/mr_violation_breakdown.tex
# Author: EK  Date: 2026-04-15
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

# ── 0. Strictly downstream PWSID list ────────────────────────────────────────
# Mirrors the "dwnstrm" sample cut in run_main_tables.r
pws_sample <- as.data.frame(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
                      col_select = c("PWSID", "minehuc_downstream_of_mine", "minehuc_mine")))
pws_ids <- unique(pws_sample$PWSID[
  pws_sample$minehuc_downstream_of_mine == 1 & pws_sample$minehuc_mine == 0])
cat("Strictly downstream PWSIDs:", length(pws_ids), "\n")

# ── 1. Load MR violations from parquet ───────────────────────────────────────
cat("Loading violations parquet...\n")
ve <- as.data.table(arrow::read_parquet(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet",
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE", "VIOLATION_CODE", "RULE_CODE")
))
cat("Total rows in parquet:", nrow(ve), "\n")

ve[, yr := as.integer(substr(NON_COMPL_PER_BEGIN_DATE, 7, 10))]
mr <- ve[PWSID %in% pws_ids &
         VIOLATION_CATEGORY_CODE == "MR" &
         yr >= 1985 & yr <= 2005]
cat("MR violations in downstream sample (1985-2005):", nrow(mr), "\n")

# Drop duplicate violation IDs (enforcement rows create duplicates)
mr <- unique(mr, by = "VIOLATION_ID")
cat("Unique MR violations:", nrow(mr), "\n")

# ── 2. Load violation-code and rule-code descriptions ────────────────────────
ref <- fread(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_REF_CODE_VALUES.csv",
  header = FALSE,
  col.names = c("VALUE_TYPE", "VALUE_CODE", "VALUE_DESCRIPTION")
)
viol_code_ref <- ref[VALUE_TYPE == "VIOLATION_CODE", .(VALUE_CODE, VALUE_DESCRIPTION)]
rule_code_ref  <- ref[VALUE_TYPE == "RULE_CODE",      .(VALUE_CODE, VALUE_DESCRIPTION)]

# ── 3. Table 1: by violation code ────────────────────────────────────────────
tab1 <- mr[, .N, by = VIOLATION_CODE]
tab1[, share := 100 * N / nrow(mr)]
tab1 <- merge(tab1, viol_code_ref, by.x = "VIOLATION_CODE", by.y = "VALUE_CODE", all.x = TRUE)
tab1[is.na(VALUE_DESCRIPTION), VALUE_DESCRIPTION := VIOLATION_CODE]
setorder(tab1, -N)
cat("\nTable 1 — by violation code:\n"); print(tab1)

# ── 4. Table 2: by rule code ─────────────────────────────────────────────────
# RULE_CODE is numeric in the parquet; cast to character for joining/display
mr[, rule_num  := suppressWarnings(as.integer(RULE_CODE))]
mr[, RULE_CODE := as.character(rule_num)]   # e.g., "332"
tab2 <- mr[!is.na(rule_num), .N, by = RULE_CODE]
tab2[, share := 100 * N / nrow(mr)]
tab2 <- merge(tab2, rule_code_ref, by.x = "RULE_CODE", by.y = "VALUE_CODE", all.x = TRUE)
tab2[is.na(VALUE_DESCRIPTION), VALUE_DESCRIPTION := RULE_CODE]
setorder(tab2, -N)
cat("\nTable 2 — by rule code:\n"); print(tab2)

# ── 5. Table 3: cross-tab violation code × rule code ─────────────────────────
tab3 <- mr[!is.na(rule_num), .N, by = .(VIOLATION_CODE, RULE_CODE)]
tab3[, share := 100 * N / nrow(mr)]
# Join descriptions
tab3 <- merge(tab3, viol_code_ref, by.x = "VIOLATION_CODE", by.y = "VALUE_CODE", all.x = TRUE)
setnames(tab3, "VALUE_DESCRIPTION", "viol_desc")
tab3 <- merge(tab3, rule_code_ref,  by.x = "RULE_CODE",     by.y = "VALUE_CODE", all.x = TRUE)
setnames(tab3, "VALUE_DESCRIPTION", "rule_desc")
tab3[is.na(viol_desc), viol_desc := VIOLATION_CODE]
tab3[is.na(rule_desc), rule_desc  := RULE_CODE]
setorder(tab3, -N)
cat("\nTable 3 — cross-tab (top 30):\n"); print(tab3[1:30])

N_total <- nrow(mr)
fn <- function(x) format(as.integer(x), big.mark = ",")
fp <- function(x) sprintf("%.1f", x)

# ── 6. LaTeX helpers ──────────────────────────────────────────────────────────
esc <- function(x) gsub("_", "\\\\_", x)

# Truncate description to fit in table column
trunc_desc <- function(x, w = 48) {
  ifelse(nchar(x) > w, paste0(substr(x, 1, w - 2), ".."), x)
}

# ── 7. Build Table 1 LaTeX ────────────────────────────────────────────────────

# Group definitions for Table 1
routine_codes <- c("03","23","24","25","26","04")
other_codes   <- setdiff(tab1$VIOLATION_CODE, routine_codes)

make_t1_rows <- function(codes, dt) {
  rows <- character(0)
  for (cd in codes) {
    r <- dt[VIOLATION_CODE == cd]
    if (nrow(r) == 0) next
    rows <- c(rows,
      paste0(r$VIOLATION_CODE, " & ", esc(trunc_desc(r$VALUE_DESCRIPTION)), " & ",
             fn(r$N), " & ", fp(r$share), " \\\\"))
  }
  rows
}

t1_lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  paste0("\\caption{MR Violations by Violation Code, 1985--2005 (Downstream CWSs)}"),
  "\\label{tab:mr_viol_code}",
  "\\small",
  "\\begin{tabular}{clrr}",
  "\\hline\\hline",
  "\\textbf{Code} & \\textbf{Description} & \\textbf{Count} & \\textbf{Share (\\%)} \\\\",
  "\\hline",
  "\\addlinespace[2pt]",
  "\\multicolumn{4}{l}{\\textit{Routine and repeat monitoring failures}} \\\\",
  "\\addlinespace[2pt]",
  make_t1_rows(routine_codes, tab1),
  "\\addlinespace[4pt]",
  "\\multicolumn{4}{l}{\\textit{Contaminant- or rule-specific monitoring failures}} \\\\",
  "\\addlinespace[2pt]",
  make_t1_rows(other_codes, tab1),
  "\\addlinespace[2pt]",
  "\\hline",
  paste0(" & \\textit{Total} & ", fn(N_total), " & 100.0 \\\\"),
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0("\\textit{Notes:} TCR = Total Coliform Rule. DBP = Disinfection Byproducts Rule. ",
         "LCR = Lead and Copper Rule. SWTR = Surface Water Treatment Rule. FBRR = Filter ",
         "Backwash Recycling Rule. ``Major'' TCR violations (codes 23, 25) indicate failure to collect ",
         "$\\geq$90\\% of required samples in a compliance period; ``minor'' violations (codes 24, 26) ",
         "indicate partial non-compliance. Sample restricted to strictly downstream CWSs ",
         "(minehuc\\_downstream\\_of\\_mine\\,=\\,1 and minehuc\\_mine\\,=\\,0). ",
         "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.parquet, SDWA\\_REF\\_CODE\\_VALUES.csv."),
  "\\end{minipage}",
  "\\end{table}"
)

# ── 8. Build Table 2 LaTeX ────────────────────────────────────────────────────
# Group by rule group
chem_rules   <- c("310","320","331","332","333","340","350")
micro_rules  <- c("110","111","121","122","123","130","140")
dbp_rules    <- c("210","220","230")

make_t2_rows <- function(rule_codes, dt) {
  rows <- character(0)
  for (rc in rule_codes) {
    r <- dt[RULE_CODE == rc]
    if (nrow(r) == 0) next
    rows <- c(rows,
      paste0(r$RULE_CODE, " & ", esc(trunc_desc(r$VALUE_DESCRIPTION)), " & ",
             fn(r$N), " & ", fp(r$share), " \\\\"))
  }
  rows
}

other_rules <- setdiff(tab2$RULE_CODE, c(chem_rules, micro_rules, dbp_rules))

t2_lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  paste0("\\caption{MR Violations by Regulatory Rule, 1985--2005 (Downstream CWSs)}"),
  "\\label{tab:mr_rule_code}",
  "\\small",
  "\\begin{tabular}{clrr}",
  "\\hline\\hline",
  "\\textbf{Rule code} & \\textbf{Rule} & \\textbf{Count} & \\textbf{Share (\\%)} \\\\",
  "\\hline",
  "\\addlinespace[2pt]",
  "\\multicolumn{4}{l}{\\textit{Chemical contaminants (Rule Group 300)}} \\\\",
  "\\addlinespace[2pt]",
  make_t2_rows(chem_rules, tab2),
  "\\addlinespace[4pt]",
  "\\multicolumn{4}{l}{\\textit{Microbial contaminants (Rule Group 100)}} \\\\",
  "\\addlinespace[2pt]",
  make_t2_rows(micro_rules, tab2),
  "\\addlinespace[4pt]",
  "\\multicolumn{4}{l}{\\textit{Disinfectants and disinfection byproducts (Rule Group 200)}} \\\\",
  "\\addlinespace[2pt]",
  make_t2_rows(dbp_rules, tab2),
  if (length(other_rules) > 0) c(
    "\\addlinespace[4pt]",
    "\\multicolumn{4}{l}{\\textit{Other rules}} \\\\",
    "\\addlinespace[2pt]",
    make_t2_rows(other_rules, tab2)
  ),
  "\\addlinespace[2pt]",
  "\\hline",
  paste0(" & \\textit{Total} & ", fn(N_total), " & 100.0 \\\\"),
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0("\\textit{Notes:} Rule codes follow EPA SDWIS classification. Mining-related outcome rules ",
         "(nitrate 331, arsenic 332, inorganic chemicals 333, radionuclides 340) together account ",
         "for the share shown. Sample restricted to strictly downstream CWSs. ",
         "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.parquet, SDWA\\_REF\\_CODE\\_VALUES.csv."),
  "\\end{minipage}",
  "\\end{table}"
)

# ── 9. Build Table 3 LaTeX (cross-tab, top combinations) ─────────────────────
# Curated groupings for the cross-tab
mining_rules    <- c("331","332","333","340")
nonmining_rules <- c("110","111","121","122","123","140","310","320")

tab3_mining    <- tab3[RULE_CODE %in% mining_rules][order(-N)]
tab3_nonmining <- tab3[RULE_CODE %in% nonmining_rules][order(-N)]
tab3_other     <- tab3[!RULE_CODE %in% c(mining_rules, nonmining_rules)][order(-N)]

make_t3_rows <- function(dt, max_rows = 20) {
  rows <- character(0)
  for (i in seq_len(min(nrow(dt), max_rows))) {
    r <- dt[i]
    desc <- paste0(esc(trunc_desc(r$viol_desc, 40)), " (", r$RULE_CODE, ")")
    rows <- c(rows,
      paste0(r$VIOLATION_CODE, " & ", r$RULE_CODE, " & ",
             esc(trunc_desc(desc, 60)), " & ",
             fn(r$N), " & ", fp(r$share), " \\\\"))
  }
  rows
}

t3_lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  paste0("\\caption{MR Violations by Violation Code and Regulatory Rule",
         " (Top Combinations), 1985--2005 (Downstream CWSs)}"),
  "\\label{tab:mr_viol_rule_crosstab}",
  "\\small",
  "\\begin{tabular}{llp{6.5cm}rr}",
  "\\hline\\hline",
  paste0("\\textbf{Viol.} & \\textbf{Rule} & \\textbf{Description} & ",
         "\\textbf{Count} & \\textbf{Share (\\%)} \\\\"),
  "\\textbf{code}  & \\textbf{code} & & & \\\\",
  "\\hline",
  "\\addlinespace[2pt]",
  paste0("\\multicolumn{5}{l}{\\textit{Mining-related outcomes ",
         "(nitrate, arsenic, inorganic chemicals, radionuclides)}} \\\\"),
  "\\addlinespace[2pt]",
  make_t3_rows(tab3_mining),
  "\\addlinespace[4pt]",
  "\\multicolumn{5}{l}{\\textit{Microbial and treatment monitoring}} \\\\",
  "\\addlinespace[2pt]",
  make_t3_rows(tab3_nonmining[RULE_CODE %in% c("110","111","121","122","123","140")]),
  "\\addlinespace[4pt]",
  "\\multicolumn{5}{l}{\\textit{Chemical phase rules (VOC, SOC) and other}} \\\\",
  "\\addlinespace[2pt]",
  make_t3_rows(tab3_nonmining[RULE_CODE %in% c("310","320")]),
  make_t3_rows(tab3_other),
  "\\addlinespace[2pt]",
  "\\hline",
  paste0(" &  & \\textit{Total} & ", fn(N_total), " & 100.0 \\\\"),
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0("\\textit{Notes:} Violation code 03 = Monitoring, Regular; 04 = ",
         "Monitoring, Check/Repeat/Confirmation; 23/24 = Monitoring, Routine Major/Minor (TCR); ",
         "25/26 = Monitoring, Repeat Major/Minor (TCR); 27 = M/R (DBP); 31 = Monitoring of ",
         "Treatment (SWTR-Unfiltered/GWR); 36 = Monitoring of Treatment (SWTR-Filter); ",
         "38 = Monitoring, Turbidity (Enhanced SWTR); 51 = Initial Tap Sampling, Pb/Cu; ",
         "52 = Follow-up or Routine LCR Tap M/R; 53 = Water Quality Parameter M/R; ",
         "56 = Source Water M/R. All violation codes reflect failure to collect required samples ",
         "or submit results on schedule; no contamination exceedance is required to trigger an ",
         "MR violation. Sample restricted to strictly downstream CWSs. ",
         "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.parquet, SDWA\\_REF\\_CODE\\_VALUES.csv."),
  "\\end{minipage}",
  "\\end{table}"
)

# ── 10. Write output ──────────────────────────────────────────────────────────
header <- c(
  "% ============================================================",
  "% Tables: MR Violation Breakdown, 1985--2005 (Downstream CWSs)",
  "% Purpose: Describes what triggers Monitoring and Reporting",
  "%          violations in SDWA data — by violation code,",
  "%          regulatory rule, and their combination.",
  "% Sample:  Strictly downstream CWSs (minehuc_downstream_of_mine=1, minehuc_mine=0)",
  "% Source:  SDWA_VIOLATIONS_ENFORCEMENT.parquet +",
  "%          SDWA_REF_CODE_VALUES.csv,",
  "%          Z:/ek559/sdwa_violations/SDWA_latest_downloads/",
  paste0("% N:       ", fn(N_total), " unique MR violations, 1985--2005"),
  "% ============================================================"
)

out_path <- "Z:/ek559/mining_wq/output/sum/mr_violation_breakdown.tex"
writeLines(
  c(header, "",
    "%------------------------------------------------------------------",
    "% Table 1: Violation codes",
    "%------------------------------------------------------------------",
    t1_lines, "", "\\clearpage", "",
    "%------------------------------------------------------------------",
    "% Table 2: Regulatory rule",
    "%------------------------------------------------------------------",
    t2_lines, "", "\\clearpage", "",
    "%------------------------------------------------------------------",
    "% Table 3: Top violation code x rule code combinations",
    "%------------------------------------------------------------------",
    t3_lines),
  out_path
)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
