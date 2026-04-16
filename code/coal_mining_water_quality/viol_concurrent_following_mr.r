# ============================================================
# Script: viol_concurrent_following_mr.r
# Purpose: For each mining/non-mining MR violation, what occurs for the same
#          PWSID and contaminant (rule code) in the concurrent year and the
#          year directly following? Tests for strategic monitoring avoidance.
# Design:  Analysis is at PWSID × rule_code × year level.
#          Concurrent  = same (PWSID, rule, year) cell as the index MR.
#          Following   = (PWSID, rule, year+1); index years restricted to ≤2004.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet (sample PWSID list)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: output/sum/viol_concurrent_following_mr.tex
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
ve[, yr       := as.integer(substr(NON_COMPL_PER_BEGIN_DATE, 7, 10))]
ve[, rule_num := suppressWarnings(as.integer(RULE_CODE))]
ve <- ve[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005 & !is.na(rule_num)]

# ── 2. Contaminant group ──────────────────────────────────────────────────────
mining_rules    <- c(331L, 332L, 333L, 340L)
nonmining_rules <- c(110L, 111L, 121L, 122L, 123L, 140L, 310L, 320L)

ve[, cgrp := fcase(
  rule_num %in% mining_rules,    "mining",
  rule_num %in% nonmining_rules, "nonmining",
  default = "other"
)]

# ── 3. Collapse to PWSID × rule × year panel ─────────────────────────────────
# For each cell: does it have at least one MR, MCL, TT?
panel <- ve[cgrp != "other", .(
  has_mr  = any(VIOLATION_CATEGORY_CODE == "MR"),
  has_mcl = any(VIOLATION_CATEGORY_CODE == "MCL"),
  has_tt  = any(VIOLATION_CATEGORY_CODE == "TT"),
  cgrp    = first(cgrp)
), by = .(PWSID, rule_num, yr)]

cat("Unique PWSID-rule-year cells:", nrow(panel), "\n")
cat("Cells with MR=TRUE (index pool):", panel[has_mr==TRUE, .N], "\n")

# ── 4. Index: PWSID-rule-year cells with an MR violation ─────────────────────
index <- panel[has_mr == TRUE]

# Concurrent classification (from same cell; MR is always true here)
index[, concurrent := fcase(
  has_mcl == TRUE,              "mcl_and_mr",
  has_tt  == TRUE,              "tt_and_mr",
  default =                    "mr_only"
)]

# ── 5. Following-year classification (join on year+1) ────────────────────────
index[, yr_plus1 := yr + 1L]

# Only include index years ≤ 2004 so following year is within sample
index_follow <- index[yr <= 2004]

follow_lookup <- panel[, .(PWSID, rule_num, yr, has_mr, has_mcl, has_tt)]

index_follow <- merge(
  index_follow,
  follow_lookup,
  by.x = c("PWSID","rule_num","yr_plus1"),
  by.y = c("PWSID","rule_num","yr"),
  all.x = TRUE,
  suffixes = c("", "_next")
)

# NAs → no violation recorded in year+1
index_follow[, following := fcase(
  has_mcl_next == TRUE,                            "mcl",
  has_tt_next  == TRUE  & has_mr_next != TRUE,     "tt_only",
  has_mr_next  == TRUE,                            "mr_only",
  default =                                       "none"
)]

# ── 6. Summary function ───────────────────────────────────────────────────────
pct <- function(dt, col, val) {
  n <- nrow(dt)
  if (n == 0) return(NA_real_)
  round(100 * sum(dt[[col]] == val, na.rm=TRUE) / n, 1)
}

summarise <- function(dt_conc, dt_follow) {
  list(
    # concurrent (all index obs)
    n_conc          = nrow(dt_conc),
    conc_mr_only    = pct(dt_conc,   "concurrent", "mr_only"),
    conc_mcl        = pct(dt_conc,   "concurrent", "mcl_and_mr"),
    conc_tt         = pct(dt_conc,   "concurrent", "tt_and_mr"),
    # following (index years ≤ 2004 only)
    n_follow        = nrow(dt_follow),
    foll_none       = pct(dt_follow, "following",  "none"),
    foll_mr_only    = pct(dt_follow, "following",  "mr_only"),
    foll_mcl        = pct(dt_follow, "following",  "mcl"),
    foll_tt_only    = pct(dt_follow, "following",  "tt_only")
  )
}

s_mine <- summarise(
  index[cgrp == "mining"],
  index_follow[cgrp == "mining"]
)
s_non <- summarise(
  index[cgrp == "nonmining"],
  index_follow[cgrp == "nonmining"]
)

# ── 7. Sanity checks ─────────────────────────────────────────────────────────
cat("\n=== Mining MR ===\n")
cat("Index cells (concurrent):", s_mine$n_conc, "\n")
cat("  MR only:        ", s_mine$conc_mr_only,  "%\n")
cat("  MCL concurrent: ", s_mine$conc_mcl,      "%\n")
cat("  TT concurrent:  ", s_mine$conc_tt,       "%\n")
cat("Index cells (following, yr≤2004):", s_mine$n_follow, "\n")
cat("  None:     ", s_mine$foll_none,    "%\n")
cat("  MR only:  ", s_mine$foll_mr_only, "%\n")
cat("  MCL:      ", s_mine$foll_mcl,     "%\n")
cat("  TT only:  ", s_mine$foll_tt_only, "%\n")

cat("\n=== Non-mining MR ===\n")
cat("Index cells (concurrent):", s_non$n_conc, "\n")
cat("  MR only:        ", s_non$conc_mr_only,  "%\n")
cat("  MCL concurrent: ", s_non$conc_mcl,      "%\n")
cat("  TT concurrent:  ", s_non$conc_tt,       "%\n")
cat("Index cells (following, yr≤2004):", s_non$n_follow, "\n")
cat("  None:     ", s_non$foll_none,    "%\n")
cat("  MR only:  ", s_non$foll_mr_only, "%\n")
cat("  MCL:      ", s_non$foll_mcl,     "%\n")
cat("  TT only:  ", s_non$foll_tt_only, "%\n")

# Verify concurrent percentages sum to ~100
cat("\nConcurrent sums (should be ~100):",
    s_mine$conc_mr_only + s_mine$conc_mcl + s_mine$conc_tt,
    s_non$conc_mr_only  + s_non$conc_mcl  + s_non$conc_tt, "\n")
cat("Following sums (should be ~100):",
    s_mine$foll_none + s_mine$foll_mr_only + s_mine$foll_mcl + s_mine$foll_tt_only,
    s_non$foll_none  + s_non$foll_mr_only  + s_non$foll_mcl  + s_non$foll_tt_only, "\n")

# ── 8. Rule-code breakdown for concurent MCL (qualitative check) ─────────────
cat("\nMining MR cells with concurrent MCL, by rule code:\n")
print(index[cgrp=="mining" & concurrent=="mcl_and_mr", .N, by=rule_num][order(-N)])
cat("\nNon-mining MR cells with concurrent MCL, by rule code:\n")
print(index[cgrp=="nonmining" & concurrent=="mcl_and_mr", .N, by=rule_num][order(-N)])

cat("\nMining MR → following MCL, by rule code:\n")
print(index_follow[cgrp=="mining" & following=="mcl", .N, by=rule_num][order(-N)])
cat("\nNon-mining MR → following MCL, by rule code:\n")
print(index_follow[cgrp=="nonmining" & following=="mcl", .N, by=rule_num][order(-N)])

# ── 9. LaTeX ─────────────────────────────────────────────────────────────────
fp  <- function(x) if (is.na(x) || is.nan(x)) "---" else sprintf("%.1f", x)
fn  <- function(x) format(as.integer(x), big.mark = ",")

lines <- c(
  "% ============================================================",
  "% Table: Concurrent and Following Violation for Same Contaminant after MR",
  "% Unit: PWSID × rule_code × year cell with MR=TRUE.",
  "% Concurrent = same cell; Following = (PWSID, rule, year+1), index yr ≤ 2004.",
  paste0("% N concurrent:  mining=", fn(s_mine$n_conc),
         ", nonmining=", fn(s_non$n_conc)),
  paste0("% N following:   mining=", fn(s_mine$n_follow),
         ", nonmining=", fn(s_non$n_follow)),
  "% ============================================================",
  "",
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Concurrent and Following Violation after an MR Violation,",
  "  by Contaminant Group, 1985--2005}",
  "\\label{tab:viol_concurrent_following}",
  "\\small",
  "\\begin{tabular}{lrr}",
  "\\hline\\hline",
  "\\textbf{} & \\textbf{Mining MR} & \\textbf{Non-mining MR} \\\\",
  "\\hline",

  # ── Panel A: Concurrent ──
  "\\addlinespace[4pt]",
  paste0("\\multicolumn{3}{l}{\\textit{Panel A: Concurrent period",
         " --- same PWSID, same contaminant, same year}} \\\\"),
  paste0("\\multicolumn{3}{l}{\\quad\\textit{(N\\,=\\,",
         fn(s_mine$n_conc), " mining; N\\,=\\,",
         fn(s_non$n_conc), " non-mining PWSID$\\times$rule$\\times$year cells)}} \\\\"),
  "\\addlinespace[2pt]",

  paste0("MR only --- no concurrent MCL or TT (\\%) & ",
         fp(s_mine$conc_mr_only), " & ", fp(s_non$conc_mr_only), " \\\\"),
  paste0("MCL concurrent with MR (\\%) & ",
         fp(s_mine$conc_mcl), " & ", fp(s_non$conc_mcl), " \\\\"),
  paste0("TT concurrent with MR, no MCL (\\%) & ",
         fp(s_mine$conc_tt), " & ", fp(s_non$conc_tt), " \\\\"),

  # ── Panel B: Following ──
  "\\addlinespace[6pt]",
  paste0("\\multicolumn{3}{l}{\\textit{Panel B: Following year",
         " --- same PWSID, same contaminant, year\\,$+$\\,1}} \\\\"),
  paste0("\\multicolumn{3}{l}{\\quad\\textit{(index violations in 1985--2004;",
         " N\\,=\\,", fn(s_mine$n_follow),
         " mining; N\\,=\\,", fn(s_non$n_follow), " non-mining)}} \\\\"),
  "\\addlinespace[2pt]",

  paste0("No violation recorded (\\%) & ",
         fp(s_mine$foll_none), " & ", fp(s_non$foll_none), " \\\\"),
  paste0("MR only --- monitoring failure again, no MCL (\\%) & ",
         fp(s_mine$foll_mr_only), " & ", fp(s_non$foll_mr_only), " \\\\"),
  paste0("MCL violation (with or without MR) (\\%) & ",
         fp(s_mine$foll_mcl), " & ", fp(s_non$foll_mcl), " \\\\"),
  paste0("TT only --- no MR or MCL (\\%) & ",
         fp(s_mine$foll_tt_only), " & ", fp(s_non$foll_tt_only), " \\\\"),

  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0(
    "\\textit{Notes:} Unit of observation is the PWSID\\,$\\times$\\,rule\\,code\\,$\\times$\\,calendar year cell. ",
    "Each cell is classified as 1 if any violation of the stated type was recorded in SDWIS for that PWSID, ",
    "rule, and year; 0 otherwise. Index cells are those with at least one MR violation. ",
    "Mining-related rule codes: nitrate (331), arsenic (332), inorganic chemicals (333), radionuclides (340). ",
    "Non-mining rule codes: total coliform (110, 111), surface/groundwater rule (121--123, 140), ",
    "VOCs (310), SOCs (320). ",
    "\\textit{Panel A} rows are mutually exclusive and sum to 100: the index cell always has MR=1, ",
    "so concurrent MCL or TT indicates a second type of violation for the same PWSID, ",
    "contaminant, and year alongside the monitoring failure. ",
    "\\textit{Panel B} rows are mutually exclusive and sum to 100: MCL takes precedence over MR and TT; ",
    "TT only requires no MCL and no MR in year\\,$+$\\,1. ",
    "``No violation'' in Panel B means no SDWIS record for that PWSID and contaminant rule in year\\,$+$\\,1; ",
    "this includes both genuine compliance and cases where the PWSID left the sample. ",
    "Index violations in 2005 are excluded from Panel B (year\\,$+$\\,1 falls outside the sample period). ",
    "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.csv."
  ),
  "\\end{minipage}",
  "\\end{table}"
)

out_path <- "Z:/ek559/mining_wq/output/sum/viol_concurrent_following_mr.tex"
writeLines(lines, out_path)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
