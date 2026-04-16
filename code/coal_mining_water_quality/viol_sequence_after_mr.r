# ============================================================
# Script: viol_sequence_after_mr.r
# Purpose: What violation follows a mining vs non-mining MR violation?
#          For each MR violation, find the next distinct violation date
#          for the same PWSID and characterise the following violation type.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet (sample PWSID list)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: output/sum/viol_sequence_after_mr.tex
# Author: EK  Date: 2026-04-15
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

# ── 0. Sample PWSIDs ─────────────────────────────────────────────────────────
pws_ids <- unique(as.data.frame(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
                      col_select = "PWSID"))$PWSID)
cat("Sample:", length(pws_ids), "PWSIDs\n")

# ── 1. Load violations ────────────────────────────────────────────────────────
cat("Loading violations...\n")
ve <- fread(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv",
  select     = c("PWSID","VIOLATION_ID","NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE","RULE_CODE"),
  na.strings = c("","NA"), showProgress = FALSE
)
ve[, yr         := as.integer(substr(NON_COMPL_PER_BEGIN_DATE, 7, 10))]
ve[, begin_date := as.Date(NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
ve <- ve[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005]

# Deduplicate to unique violations
viol <- unique(ve[, .(PWSID, VIOLATION_ID, begin_date,
                      VIOLATION_CATEGORY_CODE, RULE_CODE)])
cat("Unique violations:", nrow(viol), "\n")

# ── 2. Classify contaminant group and severity ────────────────────────────────
mining_rules    <- c(331L, 332L, 333L, 340L)
nonmining_rules <- c(110L, 111L, 121L, 122L, 123L, 140L, 310L, 320L)

viol[, rule_num := suppressWarnings(as.integer(RULE_CODE))]
viol[, cgrp := fcase(
  rule_num %in% mining_rules,    "mining",
  rule_num %in% nonmining_rules, "nonmining",
  default = "other"
)]

# Severity rank: used to pick the "most notable" violation when multiple share a date
# Higher = more severe
viol[, sev := fcase(
  VIOLATION_CATEGORY_CODE == "MCL" & cgrp == "mining",    6L,
  VIOLATION_CATEGORY_CODE == "MCL" & cgrp == "nonmining", 5L,
  VIOLATION_CATEGORY_CODE == "MCL" & cgrp == "other",     4L,
  VIOLATION_CATEGORY_CODE == "TT",                        3L,
  VIOLATION_CATEGORY_CODE == "MR"  & cgrp == "mining",    2L,
  VIOLATION_CATEGORY_CODE == "MR"  & cgrp == "nonmining", 1L,
  default = 0L
)]

# ── 3. Find next violation for each PWSID ────────────────────────────────────
# For each index violation, find minimum begin_date strictly after it in same PWSID.
# When multiple violations share that next date, keep the highest severity.

# Self-join: all pairs (i, j) where same PWSID and j.date > i.date
# Then take the minimum j.date per i, and the max-severity violation at that date.

setorder(viol, PWSID, begin_date, -sev, VIOLATION_ID)

# Assign a within-PWSID index to get the next row efficiently
viol[, row_id := .I]

# Use data.table shift within PWSID groups.
# BUT: we want "next distinct date", not "next row".
# So: collapse to PWSID × date level first (keeping max-severity per date),
# then shift.

# Step 1: per PWSID-date, keep the highest-severity violation
date_level <- viol[, .SD[which.max(sev)],
                   by = .(PWSID, begin_date)]
setorder(date_level, PWSID, begin_date)
cat("Unique PWSID-date pairs:", nrow(date_level), "\n")

# Step 2: within each PWSID, shift to get the next date's violation
date_level[, next_date       := shift(begin_date,             type = "lead"), by = PWSID]
date_level[, next_viol_cat   := shift(VIOLATION_CATEGORY_CODE, type = "lead"), by = PWSID]
date_level[, next_viol_cgrp  := shift(cgrp,                   type = "lead"), by = PWSID]
date_level[, next_rule_num   := shift(rule_num,               type = "lead"), by = PWSID]
date_level[, next_sev        := shift(sev,                    type = "lead"), by = PWSID]
date_level[, days_to_next    := as.numeric(next_date - begin_date)]

# ── 4. Re-join next-violation info back to individual MR violations ───────────
# We want one row per MR violation (not per PWSID-date),
# so join back from viol to date_level on PWSID + begin_date

mr_viol <- viol[VIOLATION_CATEGORY_CODE == "MR" & cgrp %in% c("mining","nonmining")]
mr_viol <- merge(mr_viol,
                 date_level[, .(PWSID, begin_date, next_date, next_viol_cat,
                                next_viol_cgrp, next_rule_num, days_to_next)],
                 by = c("PWSID","begin_date"), all.x = TRUE)

cat("\nMR violations for analysis:\n")
print(mr_viol[, table(cgrp)])

# ── 5. Classify the following violation ──────────────────────────────────────
# "next_type": label for the next violation, including same-rule-code distinctions
mr_viol[, next_type := fcase(
  is.na(next_viol_cat),
    "none_in_sample",
  next_viol_cat == "MCL" & next_rule_num == rule_num,
    "mcl_same_rule",
  next_viol_cat == "MCL" & next_viol_cgrp == cgrp,
    "mcl_same_group",
  next_viol_cat == "MCL",
    "mcl_other",
  next_viol_cat == "MR"  & next_rule_num == rule_num,
    "mr_same_rule",
  next_viol_cat == "MR"  & next_viol_cgrp == cgrp,
    "mr_same_group",
  next_viol_cat == "MR",
    "mr_other",
  next_viol_cat == "TT",
    "tt",
  default = "other_cat"
)]

# ── 6. Summary function ───────────────────────────────────────────────────────
summarise_seq <- function(dt) {
  n <- nrow(dt)
  type_counts <- dt[, .N, by = next_type]
  get_pct <- function(nm) {
    v <- type_counts[next_type == nm, N]
    if (length(v) == 0) 0 else round(100 * v / n, 1)
  }
  list(
    n                = n,
    pct_mcl_same_rule  = get_pct("mcl_same_rule"),
    pct_mcl_same_group = get_pct("mcl_same_group"),
    pct_mcl_other      = get_pct("mcl_other"),
    pct_mr_same_rule   = get_pct("mr_same_rule"),
    pct_mr_same_group  = get_pct("mr_same_group"),
    pct_mr_other       = get_pct("mr_other"),
    pct_tt             = get_pct("tt"),
    pct_other_cat      = get_pct("other_cat"),
    pct_none           = get_pct("none_in_sample"),
    med_days           = median(dt$days_to_next, na.rm = TRUE),
    mean_days          = mean(dt$days_to_next,   na.rm = TRUE)
  )
}

s_mine <- summarise_seq(mr_viol[cgrp == "mining"])
s_non  <- summarise_seq(mr_viol[cgrp == "nonmining"])

cat("\n=== Mining MR: next violation type ===\n")
print(as.data.frame(s_mine))
cat("\n=== Non-mining MR: next violation type ===\n")
print(as.data.frame(s_non))

# ── 7. Additional: same-rule-code transitions specifically ───────────────────
# Among mining MR violations, what share eventually (anywhere in sample) get a
# same-rule MCL?  This is a different question from "immediately next".
cat("\n--- Same-rule eventual MCL escalation ---\n")

# All MCL violations in the sample
mcl_viol <- viol[VIOLATION_CATEGORY_CODE == "MCL"]

for (grp in c("mining","nonmining")) {
  mr_sub <- mr_viol[cgrp == grp]
  # For each index MR, is there a same-rule MCL anywhere later for same PWSID?
  mcl_sub <- mcl_viol[cgrp == grp]
  # join on PWSID + rule_num, keep only MCL that comes after MR
  merged <- mr_sub[mcl_sub, on = .(PWSID, rule_num), allow.cartesian = TRUE, nomatch = 0]
  merged <- merged[i.begin_date > begin_date]  # MCL after MR
  n_with_eventual_mcl <- uniqueN(merged, by = c("PWSID","VIOLATION_ID"))
  cat(grp, "MR: N=", nrow(mr_sub),
      " — share with eventual same-rule MCL:",
      round(100 * n_with_eventual_mcl / nrow(mr_sub), 1), "%\n")
}

# ── 8. LaTeX table ────────────────────────────────────────────────────────────
fp <- function(x) if (is.na(x) || is.nan(x)) "---" else sprintf("%.1f", x)
fn <- function(x) format(as.integer(x), big.mark = ",")

n_mine <- fn(s_mine$n);  n_non <- fn(s_non$n)

lines <- c(
  "% ============================================================",
  "% Table: Violation Sequencing — What Follows a Mining vs Non-mining MR Violation?",
  "% Unit: MR violation (unique VIOLATION_ID). Next violation = highest-severity",
  "% violation at the next distinct begin_date for the same PWSID.",
  paste0("% N: mining MR = ", n_mine, ";  non-mining MR = ", n_non),
  "% ============================================================",
  "",
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Violation Following a Mining vs.\\@ Non-mining MR Violation, 1985--2005}",
  "\\label{tab:viol_sequence}",
  "\\small",
  "\\begin{tabular}{lrr}",
  "\\hline\\hline",
  paste0("\\textbf{Next violation} & \\textbf{Mining MR} & \\textbf{Non-mining MR} \\\\"),
  paste0(" & \\textit{(N=", n_mine, ")} & \\textit{(N=", n_non, ")} \\\\"),
  "\\hline",
  "\\addlinespace[4pt]",
  "\\multicolumn{3}{l}{\\textit{No subsequent violation}} \\\\",
  "\\addlinespace[2pt]",
  paste0("No further violation in 1985--2005 (\\%) & ",
         fp(s_mine$pct_none), " & ", fp(s_non$pct_none), " \\\\"),
  "\\addlinespace[4pt]",
  "\\multicolumn{3}{l}{\\textit{Monitoring/reporting violation follows}} \\\\",
  "\\addlinespace[2pt]",
  paste0("MR, same contaminant$^a$ (\\%) & ",
         fp(s_mine$pct_mr_same_rule), " & ", fp(s_non$pct_mr_same_rule), " \\\\"),
  paste0("MR, same contaminant group$^b$ (\\%) & ",
         fp(s_mine$pct_mr_same_group), " & ", fp(s_non$pct_mr_same_group), " \\\\"),
  paste0("MR, other contaminant (\\%) & ",
         fp(s_mine$pct_mr_other), " & ", fp(s_non$pct_mr_other), " \\\\"),
  "\\addlinespace[4pt]",
  "\\multicolumn{3}{l}{\\textit{Limit exceedance violation follows}} \\\\",
  "\\addlinespace[2pt]",
  paste0("MCL, same contaminant$^a$ (\\%) & ",
         fp(s_mine$pct_mcl_same_rule), " & ", fp(s_non$pct_mcl_same_rule), " \\\\"),
  paste0("MCL, same contaminant group$^b$ (\\%) & ",
         fp(s_mine$pct_mcl_same_group), " & ", fp(s_non$pct_mcl_same_group), " \\\\"),
  paste0("MCL, other contaminant (\\%) & ",
         fp(s_mine$pct_mcl_other), " & ", fp(s_non$pct_mcl_other), " \\\\"),
  "\\addlinespace[4pt]",
  "\\multicolumn{3}{l}{\\textit{Other violation type follows}} \\\\",
  "\\addlinespace[2pt]",
  paste0("Treatment technique (TT) (\\%) & ",
         fp(s_mine$pct_tt), " & ", fp(s_non$pct_tt), " \\\\"),
  paste0("Other category (\\%) & ",
         fp(s_mine$pct_other_cat), " & ", fp(s_non$pct_other_cat), " \\\\"),
  "\\addlinespace[4pt]",
  "\\multicolumn{3}{l}{\\textit{Time to next violation}} \\\\",
  "\\addlinespace[2pt]",
  paste0("Median days to next violation & ",
         fp(s_mine$med_days), " & ", fp(s_non$med_days), " \\\\"),
  paste0("Mean days to next violation & ",
         fp(s_mine$mean_days), " & ", fp(s_non$mean_days), " \\\\"),
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0(
    "\\textit{Notes:} Unit of observation is the MR violation (unique VIOLATION\\_ID). ",
    "Sample: CWS in the coal mining analysis panel, 1985--2005. ",
    "Mining-related rules: nitrate (331), arsenic (332), inorganic chemicals (333), radionuclides (340). ",
    "Non-mining rules: total coliform (110, 111), surface/groundwater rule (121--123, 140), VOCs (310), SOCs (320). ",
    "``Next violation'' is defined as the highest-severity violation beginning on the next ",
    "distinct begin date for the same PWSID; severity order is MCL mining $>$ MCL non-mining $>$ ",
    "MCL other $>$ TT $>$ MR mining $>$ MR non-mining $>$ other. ",
    "When multiple violations share the next date, the highest-severity is selected; ",
    "this is conservative for detecting MCL escalation (the MCL is surfaced if present). ",
    "``Days to next violation'' is missing for violations with no subsequent violation. ",
    "$^a$Same contaminant = same SDWIS RULE\\_CODE (e.g., an arsenic MR followed by an arsenic MCL). ",
    "$^b$Same contaminant group (but different rule code): e.g., a nitrate MR followed by an ",
    "arsenic MCL; or a total-coliform MR followed by a surface-water rule MCL. ",
    "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.csv."
  ),
  "\\end{minipage}",
  "\\end{table}"
)

out_path <- "Z:/ek559/mining_wq/output/sum/viol_sequence_after_mr.tex"
writeLines(lines, out_path)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
