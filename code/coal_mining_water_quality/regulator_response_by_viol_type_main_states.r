# ============================================================
# Script: regulator_response_by_viol_type_main_states.r
# Purpose: (1) Summary table of regulator responses (IOC MR vs IOC MCL) and
#          (2) specific enforcement action type breakdown, both restricted to
#          IOC rules (nitrate 331, arsenic 332, inorganic chemicals 333),
#          1985-2005, for all CWSs located in states that have at least one
#          CWS in the main one-step downstream 2SLS sample
#          (minehuc_downstream_of_mine==1 & minehuc_mine==0).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet (downstream states list)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_REF_CODE_VALUES.csv
# Outputs: output/sum/regulator_response_by_viol_type_main_states.tex
# Author: EK  Date: 2026-07-14
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(dplyr)
library(data.table)

# ── 0. States represented in the main one-step downstream 2SLS sample ───────
cat("Loading downstream 2SLS sample states...\n")
pws_ds <- as.data.frame(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
                      col_select = c("PWSID", "STATE_CODE",
                                     "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- pws_ds$minehuc_downstream_of_mine == 1 &
                   pws_ds$minehuc_mine == 0
downstream_states <- sort(unique(pws_ds$STATE_CODE[downstream_mask & !is.na(pws_ds$STATE_CODE)]))
cat("States in downstream 2SLS sample:", paste(downstream_states, collapse = ", "), "\n")

# All CWSs (any minehuc status) located in those states
sample_pwsids <- unique(pws_ds$PWSID[!is.na(pws_ds$STATE_CODE) &
                                      pws_ds$STATE_CODE %in% downstream_states])
cat("CWSs in main-states sample:", length(sample_pwsids), "\n\n")

# ── 1. Load violations (column subset to limit memory) ────────────────────────
cat("Reading SDWA_VIOLATIONS_ENFORCEMENT.parquet...\n")
cols_needed <- c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE", "IS_MAJOR_VIOL_IND",
                 "CALCULATED_RTC_DATE", "VIOLATION_STATUS",
                 "RULE_CODE", "ENFORCEMENT_ID",
                 "ENF_ACTION_CATEGORY", "ENF_ORIGINATOR_CODE",
                 "ENFORCEMENT_ACTION_TYPE_CODE")

ve <- as.data.table(arrow::read_parquet(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet",
  col_select = cols_needed
))
cat("Full file rows:", nrow(ve), "\n")

# ── 2. Filter to sample and period ───────────────────────────────────────────
ve[, NON_COMPL_PER_BEGIN_DATE := as.Date(NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
ve[, viol_year := as.integer(format(NON_COMPL_PER_BEGIN_DATE, "%Y"))]

ve <- ve[PWSID %in% sample_pwsids & viol_year >= 1985 & viol_year <= 2005]
cat("Rows in main-states sample (1985-2005):", nrow(ve), "\n")

ve[, CALCULATED_RTC_DATE := as.Date(CALCULATED_RTC_DATE, format = "%m/%d/%Y")]
ve[, days_to_rtc := as.numeric(CALCULATED_RTC_DATE - NON_COMPL_PER_BEGIN_DATE)]

# ── 3. Classify violations ────────────────────────────────────────────────────
ve[, rule_num := suppressWarnings(as.numeric(RULE_CODE))]

cat("\nVIOLATION_CATEGORY_CODE distribution:\n")
print(sort(table(ve$VIOLATION_CATEGORY_CODE, useNA = "ifany"), decreasing = TRUE))

# ── 4. Collapse to violation level ────────────────────────────────────────────
ve[, enf_rank := fcase(
  ENF_ACTION_CATEGORY == "Formal",    3L,
  ENF_ACTION_CATEGORY == "Resolving", 2L,
  ENF_ACTION_CATEGORY == "Informal",  1L,
  default = 0L
)]
ve[, federal_flag := as.integer(!is.na(ENF_ORIGINATOR_CODE) & ENF_ORIGINATOR_CODE == "F")]

viol <- ve[, .(
  viol_type    = first(VIOLATION_CATEGORY_CODE),
  rule_num     = first(rule_num),
  is_major_raw = first(IS_MAJOR_VIOL_IND),
  viol_status  = first(VIOLATION_STATUS),
  days_to_rtc  = first(days_to_rtc),
  enf_rank     = max(enf_rank,    na.rm = TRUE),
  federal_enf  = max(federal_flag, na.rm = TRUE)
), by = .(PWSID, VIOLATION_ID)]

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
    pct_no_enf      = 100 * mean(df$no_enf,         na.rm = TRUE),
    pct_any_enf     = 100 * mean(df$any_enf,         na.rm = TRUE),
    pct_informal    = 100 * mean(df$any_informal,    na.rm = TRUE),
    pct_resolving   = 100 * mean(df$any_resolving,   na.rm = TRUE),
    pct_formal      = 100 * mean(df$any_formal,      na.rm = TRUE),
    pct_federal     = 100 * mean(df$federal_enf,     na.rm = TRUE),
    pct_major       = 100 * mean(df$is_major_y,      na.rm = TRUE),
    pct_resolved    = 100 * mean(df$status_resolved, na.rm = TRUE),
    pct_archived    = 100 * mean(df$status_archived, na.rm = TRUE),
    pct_open        = 100 * mean(df$status_open,     na.rm = TRUE),
    med_days        = median(df$days_to_rtc, na.rm = TRUE),
    mean_days       = mean(df$days_to_rtc,   na.rm = TRUE)
  )
}

# ── 6. Compute statistics ─────────────────────────────────────────────────────
ioc_rules <- c(331, 332, 333)
viol_df   <- as.data.frame(viol)

s <- list(
  ioc_mr  = summarize_group(viol_df[viol_df$viol_type == "MR"  & viol_df$rule_num %in% ioc_rules, ]),
  ioc_mcl = summarize_group(viol_df[viol_df$viol_type == "MCL" & viol_df$rule_num %in% ioc_rules, ])
)

cat("\n=== Summary: IOC MR vs IOC MCL violations ===\n")
cat(sprintf("%-40s %12s %12s\n", "Statistic", "IOC MR", "IOC MCL"))
cat(strrep("-", 66), "\n")
for (stat in names(s$ioc_mr)) {
  vals <- sapply(c("ioc_mr", "ioc_mcl"), function(g) s[[g]][[stat]])
  if (stat == "n") {
    cat(sprintf("%-40s %12s %12s\n", "N violations",
                format(vals[1], big.mark = ","), format(vals[2], big.mark = ",")))
  } else if (stat %in% c("med_days", "mean_days")) {
    cat(sprintf("%-40s %12.1f %12.1f\n", stat, vals[1], vals[2]))
  } else {
    cat(sprintf("%-40s %11.1f%% %11.1f%%\n", stat, vals[1], vals[2]))
  }
}

# ── 7. LaTeX output — Table 1: regulator response summary ────────────────────
fmt_pct  <- function(x) sprintf("%.1f", x)
fmt_n    <- function(x) format(x, big.mark = ",", scientific = FALSE)
fmt_days <- function(x) if (is.nan(x) || is.na(x)) "---" else sprintf("%.0f", x)

make_frame <- function(grps, col_headers, frame_title, label, notes) {
  g <- lapply(grps, function(nm) s[[nm]])

  lines <- c(
    paste0("\\label{", label, "}"),
    "\\begin{adjustbox}{max width=\\textwidth, max totalheight=\\textheight, keepaspectratio, center}",
    "\\begin{minipage}{\\textwidth}",
    "\\begin{tabular}{lrr}",
    "\\hline\\hline",
    paste0("\\textbf{Regulator response} & \\textbf{", col_headers[1], "} & \\textbf{",
           col_headers[2], "} \\\\"),
    "\\hline",
    paste0("\\textit{N violations} & ", fmt_n(g[[1]]$n), " & ", fmt_n(g[[2]]$n), " \\\\"),
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
    "\\end{tabular}",
    "\\end{minipage}",
    "\\end{adjustbox}",
    paste0("\\par\\smallskip{\\tiny ", notes, "}")
  )
  paste(lines, collapse = "\n")
}

state_list <- paste(sort(downstream_states[downstream_states != "0"]), collapse = ", ")
n_cws_fmt  <- format(length(sample_pwsids), big.mark = ",")

shared_notes <- paste0(
  "Unit of observation: violation (unique VIOLATION\\_ID). ",
  "Sample: all CWSs in states with at least one CWS in the main downstream 2SLS sample ",
  "(minehuc\\_downstream\\_of\\_mine\\,=\\,1 and minehuc\\_mine\\,=\\,0), ",
  "1985--2005 (", n_cws_fmt, " CWSs; states: ", state_list, "). ",
  "IOC rules: nitrate (331), arsenic (332), inorganic chemicals (333). ",
  "Multiple enforcement actions per violation assigned the most severe (Formal $>$ Resolving $>$ Informal). ",
  "Days to compliance = CALCULATED\\_RTC\\_DATE $-$ NON\\_COMPL\\_PER\\_BEGIN\\_DATE. ",
  "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.parquet."
)

t1 <- make_frame(
  grps        = c("ioc_mr", "ioc_mcl"),
  col_headers = c("IOC MR", "IOC MCL"),
  frame_title = "Regulator Response by IOC Violation Type, 1985--2005",
  label       = "tab:reg_response_ioc_mainstates",
  notes       = shared_notes
)

# ── 8. Specific enforcement action types table ────────────────────────────────
cat("\nBuilding specific enforcement action types table...\n")

# Load REF codes for enforcement action types
ref_all <- fread(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_REF_CODE_VALUES.csv",
  header = FALSE, col.names = c("VALUE_TYPE", "VALUE_CODE", "VALUE_DESCRIPTION")
)
ref_enf <- ref_all[VALUE_TYPE == "ENFORCEMENT_ACTION_TYPE_CODE",
                   .(VALUE_CODE, VALUE_DESCRIPTION)]

# Use action-level rows that have an actual enforcement action and are IOC-rule violations
ve_enf <- ve[!is.na(ENFORCEMENT_ID) & rule_num %in% ioc_rules &
             VIOLATION_CATEGORY_CODE %in% c("MR", "MCL")]
cat("Enforcement action rows (IOC rules, main-states, 1985-2005):", nrow(ve_enf), "\n")

grp_names_enf <- c("mr_ioc", "mcl_ioc")
groups_enf <- list(
  mr_ioc  = ve_enf[VIOLATION_CATEGORY_CODE == "MR"],
  mcl_ioc = ve_enf[VIOLATION_CATEGORY_CODE == "MCL"]
)
totals_enf <- sapply(groups_enf, nrow)
cat("Enforcement actions — MR IOC:", totals_enf["mr_ioc"],
    " MCL IOC:", totals_enf["mcl_ioc"], "\n")

tabs_enf <- lapply(names(groups_enf), function(nm) {
  g <- groups_enf[[nm]]
  ct <- g[, .N, by = .(ENF_ACTION_CATEGORY, ENFORCEMENT_ACTION_TYPE_CODE)]
  ct[, share := 100 * N / nrow(g)]
  setnames(ct, c("N", "share"), paste0(c("n_", "s_"), nm))
  ct
})

wide_enf <- Reduce(function(a, b)
  merge(a, b, by = c("ENF_ACTION_CATEGORY", "ENFORCEMENT_ACTION_TYPE_CODE"), all = TRUE),
  tabs_enf)

for (col in c(paste0("s_", grp_names_enf), paste0("n_", grp_names_enf))) {
  set(wide_enf, which(is.na(wide_enf[[col]])), col, 0)
}

wide_enf <- merge(wide_enf, ref_enf,
                  by.x = "ENFORCEMENT_ACTION_TYPE_CODE", by.y = "VALUE_CODE", all.x = TRUE)
wide_enf[is.na(VALUE_DESCRIPTION), VALUE_DESCRIPTION := ENFORCEMENT_ACTION_TYPE_CODE]
wide_enf[, max_share := pmax(s_mr_ioc, s_mcl_ioc)]

formal_rows_enf    <- wide_enf[ENF_ACTION_CATEGORY == "Formal"][order(-max_share)]
resolving_rows_enf <- wide_enf[ENF_ACTION_CATEGORY == "Resolving"][order(-max_share)]
informal_keep_enf  <- wide_enf[ENF_ACTION_CATEGORY == "Informal" & max_share >= 1.0][order(-max_share)]
informal_other_enf <- wide_enf[ENF_ACTION_CATEGORY == "Informal" & max_share <  1.0]

other_row_enf <- data.table(
  ENFORCEMENT_ACTION_TYPE_CODE = "---",
  ENF_ACTION_CATEGORY          = "Informal",
  VALUE_DESCRIPTION            = "All other informal actions",
  s_mr_ioc  = sum(informal_other_enf$s_mr_ioc),
  s_mcl_ioc = sum(informal_other_enf$s_mcl_ioc),
  n_mr_ioc  = sum(informal_other_enf$n_mr_ioc),
  n_mcl_ioc = sum(informal_other_enf$n_mcl_ioc),
  max_share = NA_real_
)

fp_e  <- function(x) if (is.na(x)) "---" else if (x == 0) "0.0" else sprintf("%.1f", x)
fn_e  <- function(x) format(as.integer(x), big.mark = ",")
esc_e <- function(x) gsub("_", "\\\\_", x)

enf_lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  paste0("\\caption{Specific Enforcement Actions for IOC Violations, 1985--2005",
         " (Main States Sample)}"),
  "\\label{tab:enf_action_type_ioc_mainstates}",
  "\\small",
  "\\begin{tabular}{llp{6.5cm}rr}",
  "\\hline\\hline",
  paste0("\\textbf{Cat.} & \\textbf{Code} & \\textbf{Description} & ",
         "\\textbf{IOC MR (\\%)} & \\textbf{IOC MCL (\\%)} \\\\"),
  paste0(" & & & \\textit{(N=", fn_e(s$ioc_mr$n), ")} & \\textit{(N=",
         fn_e(s$ioc_mcl$n), ")} \\\\"),
  "\\hline"
)

sections_enf <- list(
  list(label = "\\textit{Formal enforcement}",
       rows  = formal_rows_enf),
  list(label = "\\textit{Informal enforcement}",
       rows  = rbindlist(list(informal_keep_enf, other_row_enf), fill = TRUE)),
  list(label = "\\textit{Resolving (compliance achieved)}",
       rows  = resolving_rows_enf)
)

for (sec in sections_enf) {
  enf_lines <- c(enf_lines,
    "\\addlinespace[4pt]",
    paste0("\\multicolumn{5}{l}{", sec$label, "} \\\\"),
    "\\addlinespace[2pt]"
  )
  for (i in seq_len(nrow(sec$rows))) {
    r         <- sec$rows[i]
    cat_label <- if (i == 1) esc_e(r$ENF_ACTION_CATEGORY) else ""
    cd        <- esc_e(r$ENFORCEMENT_ACTION_TYPE_CODE)
    dsc       <- esc_e(r$VALUE_DESCRIPTION)
    enf_lines <- c(enf_lines,
      paste0(cat_label, " & ", cd, " & ", dsc, " & ",
             fp_e(r$s_mr_ioc), " & ", fp_e(r$s_mcl_ioc), " \\\\")
    )
  }
}

enf_notes <- paste0(
  "\\textit{Notes:} Unit of observation is the enforcement action row in ",
  "SDWA\\_VIOLATIONS\\_ENFORCEMENT.csv. Entries show the share (\\%) of all enforcement ",
  "actions within each column group that are of the specified type. ",
  "MR = monitoring/reporting violation; MCL = maximum contaminant level violation; ",
  "both restricted to IOC rules (nitrate 331, arsenic 332, inorganic chemicals 333). ",
  "A violation may generate multiple enforcement actions; rows are enforcement actions, not violations. ",
  "Enforcement categories follow EPA SDWIS classification: ",
  "\\textit{Formal} = legally binding instruments (administrative orders, consent decrees, penalties, ",
  "civil/criminal referrals); ",
  "\\textit{Informal} = advisory actions and notices (notices of violation, public notification requests, ",
  "compliance meetings, technical assistance visits); ",
  "\\textit{Resolving} = closure actions recording that the system returned to compliance. ",
  "``All other informal actions'' aggregates codes each below 1\\% in every column. ",
  "Sample: all CWSs in states with at least one CWS in the main downstream 2SLS sample ",
  "(minehuc\\_downstream\\_of\\_mine\\,=\\,1 and minehuc\\_mine\\,=\\,0), ",
  "1985--2005 (", n_cws_fmt, " CWSs; states: ", state_list, "). ",
  "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.parquet, SDWA\\_REF\\_CODE\\_VALUES.csv."
)

enf_lines <- c(enf_lines,
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  enf_notes,
  "\\end{minipage}",
  "\\end{table}"
)

cat("\nDisplay: enforcement action type breakdown\n")
print(wide_enf[order(ENF_ACTION_CATEGORY, -max_share),
               .(ENF_ACTION_CATEGORY, ENFORCEMENT_ACTION_TYPE_CODE,
                 VALUE_DESCRIPTION, s_mr_ioc, s_mcl_ioc)],
      nrows = 60)

# ── 9. Write output ───────────────────────────────────────────────────────────
header <- paste0(
  "% ============================================================\n",
  "% Tables: Regulator Response by IOC Violation Type, 1985--2005\n",
  "% Purpose: (1) Share of violations receiving each type of regulator response,\n",
  "%          conditional on violation category (MR vs MCL) for IOC rules;\n",
  "%          (2) specific enforcement action type breakdown.\n",
  "% Sample:  All CWSs in states with >=1 CWS in the main downstream 2SLS sample.\n",
  "% Source:  SDWA_VIOLATIONS_ENFORCEMENT.parquet\n",
  "% N IOC MR:  ", fmt_n(s$ioc_mr$n), " violations\n",
  "% N IOC MCL: ", fmt_n(s$ioc_mcl$n), " violations\n",
  "% ============================================================\n"
)

out_path <- "Z:/ek559/mining_wq/output/sum/regulator_response_by_viol_type_main_states.tex"
writeLines(
  paste(header,
        "%------------------------------------------------------------------\n",
        "% Table 1: Regulator response summary\n",
        "%------------------------------------------------------------------\n",
        t1,
        "\n\\clearpage\n",
        "%------------------------------------------------------------------\n",
        "% Table 2: Specific enforcement action types\n",
        "%------------------------------------------------------------------\n",
        paste(enf_lines, collapse = "\n"),
        sep = "\n"),
  out_path
)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
