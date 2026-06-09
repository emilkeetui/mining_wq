# ============================================================
# Script: regulator_response_by_viol_type.r
# Purpose: Summary tables of regulator responses conditional on violation type
#          (MR vs MCL) and contaminant category (mining vs non-mining), 1985-2005
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet (sample PWSID list)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: output/sum/regulator_response_by_viol_type.tex
# Author: EK  Date: 2026-04-15
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(dplyr)
library(data.table)

# ── 0. Sample PWSID list — CWSs in the main downstream sample ────────────────
# Strictly downstream: minehuc_downstream_of_mine == 1 AND minehuc_mine == 0
cat("Loading downstream sample PWS IDs...\n")
pws_ds <- as.data.frame(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
                      col_select = c("PWSID", "STATE_CODE",
                                     "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- pws_ds$minehuc_downstream_of_mine == 1 &
                   pws_ds$minehuc_mine == 0
sample_pwsids   <- unique(pws_ds$PWSID[downstream_mask])
downstream_states <- unique(pws_ds$STATE_CODE[downstream_mask & !is.na(pws_ds$STATE_CODE)])
cat("CWSs in downstream sample:", length(sample_pwsids), "\n")
cat("States represented:", paste(sort(downstream_states), collapse = ", "), "\n\n")

# ── 1. Load violations (column subset to limit memory) ────────────────────────
cat("Reading SDWA_VIOLATIONS_ENFORCEMENT.csv (3.7 GB — using fread)...\n")
cols_needed <- c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE", "IS_MAJOR_VIOL_IND",
                 "CALCULATED_RTC_DATE", "VIOLATION_STATUS",
                 "RULE_CODE", "ENFORCEMENT_ID",
                 "ENF_ACTION_CATEGORY", "ENF_ORIGINATOR_CODE")

ve <- fread(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv",
  select      = cols_needed,
  na.strings  = c("", "NA", "--->'"),
  showProgress = TRUE
)
cat("Full file rows:", nrow(ve), "\n")

# ── 2. Filter to sample and period ───────────────────────────────────────────
ve[, NON_COMPL_PER_BEGIN_DATE := as.Date(NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
ve[, viol_year := as.integer(format(NON_COMPL_PER_BEGIN_DATE, "%Y"))]

ve <- ve[PWSID %in% sample_pwsids & viol_year >= 1985 & viol_year <= 2005]
cat("Rows in sample (1985-2005):", nrow(ve), "\n")

ve[, CALCULATED_RTC_DATE := as.Date(CALCULATED_RTC_DATE, format = "%m/%d/%Y")]
ve[, days_to_rtc := as.numeric(CALCULATED_RTC_DATE - NON_COMPL_PER_BEGIN_DATE)]

# ── 3. Classify violations ────────────────────────────────────────────────────
# Mining-related rules: 331=nitrates, 332=arsenic, 333=inorganic chem, 340=radionuclides
# Non-mining rules: 110/111=total coliform, 121-123/140=surface/groundwater, 310=VOC, 320=SOC
mining_rules    <- c(331, 332, 333, 340)
nonmining_rules <- c(110, 111, 121, 122, 123, 140, 310, 320)

ve[, rule_num := suppressWarnings(as.numeric(RULE_CODE))]
ve[, contaminant_group := fcase(
  rule_num %in% mining_rules,    "mining",
  rule_num %in% nonmining_rules, "nonmining",
  default = "other"
)]

cat("\nVIOLATION_CATEGORY_CODE distribution:\n")
print(sort(table(ve$VIOLATION_CATEGORY_CODE, useNA = "ifany"), decreasing = TRUE))
cat("\nContaminant group distribution:\n")
print(sort(table(ve$contaminant_group, useNA = "ifany"), decreasing = TRUE))

# ── 4. Collapse to violation level ────────────────────────────────────────────
# Multiple rows per VIOLATION_ID when multiple enforcement actions were issued.
# Take the most severe enforcement action per violation, OR-combine federal flag.

ve[, enf_rank := fcase(
  ENF_ACTION_CATEGORY == "Formal",    3L,
  ENF_ACTION_CATEGORY == "Resolving", 2L,
  ENF_ACTION_CATEGORY == "Informal",  1L,
  default = 0L
)]
ve[, federal_flag := as.integer(!is.na(ENF_ORIGINATOR_CODE) & ENF_ORIGINATOR_CODE == "F")]

viol <- ve[, .(
  viol_type         = first(VIOLATION_CATEGORY_CODE),
  contaminant_group = first(contaminant_group),
  rule_num          = first(rule_num),
  is_major_raw      = first(IS_MAJOR_VIOL_IND),
  viol_status       = first(VIOLATION_STATUS),
  days_to_rtc       = first(days_to_rtc),
  enf_rank          = max(enf_rank,    na.rm = TRUE),
  federal_enf       = max(federal_flag, na.rm = TRUE)
), by = .(PWSID, VIOLATION_ID, viol_year)]

# Derive binary outcome indicators
viol[, any_enf        := as.integer(enf_rank > 0)]
viol[, any_formal     := as.integer(enf_rank == 3)]
viol[, any_resolving  := as.integer(enf_rank == 2)]
viol[, any_informal   := as.integer(enf_rank == 1)]
viol[, no_enf         := as.integer(enf_rank == 0)]
viol[, is_major_y     := as.integer(!is.na(is_major_raw) & is_major_raw == "Y")]
viol[, status_resolved := as.integer(!is.na(viol_status) & viol_status == "Resolved")]
viol[, status_archived := as.integer(!is.na(viol_status) & viol_status == "Archived")]
viol[, status_open    := as.integer(!is.na(viol_status) & viol_status %in% c("Addressed", "Unaddressed"))]

cat("\nViolation-level N:", nrow(viol), "\n")
cat("Viol type distribution (violation level):\n")
print(sort(table(viol$viol_type, useNA = "ifany"), decreasing = TRUE))

# ── 5. Summary function ───────────────────────────────────────────────────────
summarize_group <- function(df) {
  n <- nrow(df)
  list(
    n               = n,
    pct_no_enf      = 100 * mean(df$no_enf,        na.rm = TRUE),
    pct_any_enf     = 100 * mean(df$any_enf,        na.rm = TRUE),
    pct_informal    = 100 * mean(df$any_informal,   na.rm = TRUE),
    pct_resolving   = 100 * mean(df$any_resolving,  na.rm = TRUE),
    pct_formal      = 100 * mean(df$any_formal,     na.rm = TRUE),
    pct_federal     = 100 * mean(df$federal_enf,    na.rm = TRUE),
    pct_major       = 100 * mean(df$is_major_y,     na.rm = TRUE),
    pct_resolved    = 100 * mean(df$status_resolved, na.rm = TRUE),
    pct_archived    = 100 * mean(df$status_archived, na.rm = TRUE),
    pct_open        = 100 * mean(df$status_open,    na.rm = TRUE),
    med_days        = median(df$days_to_rtc, na.rm = TRUE),
    mean_days       = mean(df$days_to_rtc,   na.rm = TRUE)
  )
}

# ── 6. Compute statistics for each conditioning group ─────────────────────────
# IOC rules: nitrate (331), arsenic (332), inorganic chemicals (333)
ioc_rules <- c(331, 332, 333)

viol_df <- as.data.frame(viol)

s <- list(
  ioc_mr  = summarize_group(viol_df[viol_df$viol_type == "MR"  & viol_df$rule_num %in% ioc_rules, ]),
  ioc_mcl = summarize_group(viol_df[viol_df$viol_type == "MCL" & viol_df$rule_num %in% ioc_rules, ])
)

# Print to console for verification
cat("\n=== Summary: IOC MR vs IOC MCL violations ===\n")
cat(sprintf("%-40s %12s %12s\n", "Statistic", "IOC MR", "IOC MCL"))
cat(strrep("-", 66), "\n")
for (stat in names(s$ioc_mr)) {
  vals <- sapply(c("ioc_mr","ioc_mcl"), function(g) s[[g]][[stat]])
  if (stat == "n") {
    cat(sprintf("%-40s %12s %12s\n", "N violations",
                format(vals[1], big.mark=","), format(vals[2], big.mark=",")))
  } else if (stat %in% c("med_days","mean_days")) {
    cat(sprintf("%-40s %12.1f %12.1f\n", stat, vals[1], vals[2]))
  } else {
    cat(sprintf("%-40s %11.1f%% %11.1f%%\n", stat, vals[1], vals[2]))
  }
}

# ── 7. LaTeX output ───────────────────────────────────────────────────────────
fmt_pct <- function(x) sprintf("%.1f", x)
fmt_n   <- function(x) format(x, big.mark = ",", scientific = FALSE)
fmt_days <- function(x) if (is.nan(x) || is.na(x)) "---" else sprintf("%.0f", x)

make_frame <- function(grps, col_headers, frame_title, label, notes) {
  g <- lapply(grps, function(nm) s[[nm]])

  lines <- c(
    paste0("\\begin{frame}{", frame_title, "}"),
    paste0("\\label{", label, "}"),
    "\\resizebox{\\textwidth}{!}{%",
    paste0("\\begin{tabular}{lrr}"),
    "\\hline\\hline",
    paste0("\\textbf{Regulator response} & \\textbf{", col_headers[1], "} & \\textbf{",
           col_headers[2], "} \\\\"),
    "\\hline",
    paste0("\\textit{N violations} & ",
           fmt_n(g[[1]]$n), " & ", fmt_n(g[[2]]$n), " \\\\"),
    "\\addlinespace[3pt]",
    "\\multicolumn{3}{l}{\\textit{Enforcement intensity}} \\\\",
    "\\addlinespace[1pt]",
    paste0("No enforcement received (\\%) & ",
           fmt_pct(g[[1]]$pct_no_enf), " & ", fmt_pct(g[[2]]$pct_no_enf), " \\\\"),
    paste0("Any enforcement received (\\%) & ",
           fmt_pct(g[[1]]$pct_any_enf), " & ", fmt_pct(g[[2]]$pct_any_enf), " \\\\"),
    paste0("\\quad Informal (\\%) & ",
           fmt_pct(g[[1]]$pct_informal), " & ", fmt_pct(g[[2]]$pct_informal), " \\\\"),
    paste0("\\quad Resolving (\\%) & ",
           fmt_pct(g[[1]]$pct_resolving), " & ", fmt_pct(g[[2]]$pct_resolving), " \\\\"),
    paste0("\\quad Formal (\\%) & ",
           fmt_pct(g[[1]]$pct_formal), " & ", fmt_pct(g[[2]]$pct_formal), " \\\\"),
    paste0("Federal enforcement (\\%) & ",
           fmt_pct(g[[1]]$pct_federal), " & ", fmt_pct(g[[2]]$pct_federal), " \\\\"),
    paste0("Major violation (\\%) & ",
           fmt_pct(g[[1]]$pct_major), " & ", fmt_pct(g[[2]]$pct_major), " \\\\"),
    "\\addlinespace[3pt]",
    "\\multicolumn{3}{l}{\\textit{Return to compliance}} \\\\",
    "\\addlinespace[1pt]",
    paste0("Status: Resolved (\\%) & ",
           fmt_pct(g[[1]]$pct_resolved), " & ", fmt_pct(g[[2]]$pct_resolved), " \\\\"),
    paste0("Status: Archived (\\%) & ",
           fmt_pct(g[[1]]$pct_archived), " & ", fmt_pct(g[[2]]$pct_archived), " \\\\"),
    paste0("Status: Open (\\%) & ",
           fmt_pct(g[[1]]$pct_open), " & ", fmt_pct(g[[2]]$pct_open), " \\\\"),
    paste0("Median days to compliance & ",
           fmt_days(g[[1]]$med_days), " & ", fmt_days(g[[2]]$med_days), " \\\\"),
    paste0("Mean days to compliance & ",
           fmt_days(g[[1]]$mean_days), " & ", fmt_days(g[[2]]$mean_days), " \\\\"),
    "\\hline\\hline",
    "\\end{tabular}%",
    "}",
    paste0("{\\tiny ", notes, "}"),
    "\\end{frame}"
  )
  paste(lines, collapse = "\n")
}

state_list <- paste(sort(downstream_states[downstream_states != "0"]), collapse = ", ")
n_cws_fmt  <- format(length(sample_pwsids), big.mark = ",")

shared_notes <- paste0(
  "Unit of observation: violation (unique VIOLATION\\_ID). ",
  "Sample: ", n_cws_fmt, " CWSs in the main downstream 2SLS sample (one step downstream, not colocated with mines), 1985--2005 ",
  "(", state_list, "). ",
  "IOC rules: nitrate (331), arsenic (332), inorganic chemicals (333). ",
  "Multiple enforcement actions per violation assigned the most severe (Formal $>$ Resolving $>$ Informal). ",
  "Days to compliance = CALCULATED\\_RTC\\_DATE $-$ NON\\_COMPL\\_PER\\_BEGIN\\_DATE. ",
  "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.csv."
)

t1 <- make_frame(
  grps        = c("ioc_mr", "ioc_mcl"),
  col_headers = c("IOC MR", "IOC MCL"),
  frame_title = "Regulator Response by IOC Violation Type, 1985--2005",
  label       = "tab:reg_response_ioc",
  notes       = shared_notes
)

header <- paste0(
  "% ============================================================\n",
  "% Table: Regulator Response by IOC Violation Type, 1985--2005\n",
  "% Purpose: Share of violations receiving each type of regulator response,\n",
  "%          conditional on violation category (MR vs MCL) for IOC rules\n",
  "%          (nitrate 331, arsenic 332, inorganic chemicals 333).\n",
  "% Sample:  Main downstream 2SLS sample (one step downstream, not colocated).\n",
  "% Source:  SDWA_VIOLATIONS_ENFORCEMENT.csv\n",
  "% N IOC MR:  ", fmt_n(s$ioc_mr$n), " violations\n",
  "% N IOC MCL: ", fmt_n(s$ioc_mcl$n), " violations\n",
  "% ============================================================\n"
)

out_path <- "Z:/ek559/mining_wq/output/sum/regulator_response_by_viol_type.tex"
writeLines(
  paste(header, t1, sep = "\n"),
  out_path
)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
