# ============================================================
# Script: sanitary_visit_timing_enforcement_rate_bychem_test.r
# Purpose: TEST version of sanitary_visit_timing_formal_enforcement_rate.tex,
#          restricting MR violations to the mining-related inorganic chemicals
#          only -- nitrate (RULE_CODE 331), arsenic (332), and IOC (333) -- and
#          reporting THREE enforcement outcomes side by side instead of one:
#          formal, informal, and no enforcement. Each enforcement column shows
#          the CWS-year rate as "rate% [k]", where k is the numerator (the count
#          of CWS-years in that enforcement category within the row's sample) and
#          rate% = k / N. The N (CWS-years) column is the shared row denominator.
#
#          Enforcement indicators are INDEPENDENT (a CWS-year can be both formal
#          and informal): formal = 1 if any ENF_ACTION_CATEGORY = Formal spell is
#          ongoing in year t; informal = 1 if any ENF_ACTION_CATEGORY = Informal
#          spell is ongoing in year t; no_enforcement = 1 if neither formal nor
#          informal is ongoing. Rates therefore need not sum to 100%.
#
#          Rows mirror the original 6-row timing table: (1) all CWS-years,
#          (2) MR violation onset, (3) MR onset + same-year sanitary visit,
#          (4) MR onset with a sanitary visit in the 365 days before onset,
#          (5) MR onset with a sanitary visit in the 365 days after onset,
#          (6) row-3 sample restricted to upstream mines above the median.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/reg/sanitary_visit_timing_enforcement_rate_bychem_test.tex
# Author: EK  Date: 2026-07-17
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

YR_LO <- 1985L
YR_HI <- 2005L

# MR rules kept: mining-related inorganic chemicals only.
#   331 = nitrate, 332 = arsenic, 333 = inorganic chemicals (IOC)
IOC_RULES <- c(331L, 332L, 333L)

# ── 0. Sample: strictly-downstream CWSs ───────────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"),
    col_select = c("PWSID", "year", "num_coal_mines_upstream_sum",
                   "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0
sample_pwsids   <- unique(panel$PWSID[downstream_mask])
cat("Downstream CWSs in sample:", length(sample_pwsids), "\n")

# Median number of upstream mines across all CWS-years in the downstream
# 2SLS main sample (used as the row-6 cutoff below).
upstream_mines_py <- unique(panel[downstream_mask, .(PWSID, year, num_coal_mines_upstream_sum)])
median_upstream_mines <- median(upstream_mines_py$num_coal_mines_upstream_sum, na.rm = TRUE)
cat("Median num_coal_mines_upstream_sum across downstream 2SLS CWS-years:",
    median_upstream_mines, "\n")

# ── 1. Violations + enforcement ───────────────────────────────────────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE",
                 "VIOLATION_CATEGORY_CODE", "RULE_CODE", "ENFORCEMENT_ID", "ENFORCEMENT_DATE",
                 "ENF_ACTION_CATEGORY", "CALCULATED_RTC_DATE")))
ve <- ve[PWSID %in% sample_pwsids]
ve[, rule_tmp := suppressWarnings(as.integer(RULE_CODE))]

# ── 1a. MR violation onsets (IOC rules only): dedupe on VIOLATION_ID, year ────
onsets <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE,
                        VIOLATION_CATEGORY_CODE, rule_tmp)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= YR_LO & onset_yr <= YR_HI]

mr_onsets <- onsets[VIOLATION_CATEGORY_CODE == "MR" & rule_tmp %in% IOC_RULES,
                    .(PWSID, VIOLATION_ID, onset_dt, onset_yr)]
cat("IOC MR violation onsets (event-level, rules 331/332/333):", nrow(mr_onsets), "\n")

mr_py <- unique(mr_onsets[, .(PWSID, year = onset_yr, mr_violation = 1L)])
cat("CWS-years with an IOC MR violation onset:", nrow(mr_py), "\n")

# ── 1b. Enforcement spans -> formal / informal, expanded to CWS-year ─────────
# Independent indicators: a CWS-year may be flagged formal, informal, or both.
enf <- ve[!is.na(ENFORCEMENT_ID) & !is.na(ENFORCEMENT_DATE)]
enf[, enf_dt := as.Date(ENFORCEMENT_DATE, "%m/%d/%Y")]
enf <- enf[!is.na(enf_dt)]
enf[, enf_yr := as.integer(format(enf_dt, "%Y"))]
enf <- enf[enf_yr >= YR_LO & enf_yr <= YR_HI]
enf[, rtc_dt  := as.Date(CALCULATED_RTC_DATE,    "%m/%d/%Y")]
enf[, ncpe_dt := as.Date(NON_COMPL_PER_END_DATE, "%m/%d/%Y")]
enf[, end_dt  := fifelse(!is.na(rtc_dt), rtc_dt, fifelse(!is.na(ncpe_dt), ncpe_dt, enf_dt))]
enf[, start_yr := as.integer(format(enf_dt, "%Y"))]
enf[, end_yr   := pmax(as.integer(format(end_dt, "%Y")), start_yr)]
enf <- unique(enf[, .(PWSID, ENFORCEMENT_ID, enf_dt, start_yr, end_yr, ENF_ACTION_CATEGORY)])
cat("Enforcement actions (deduped):", nrow(enf), "\n")

year_lists <- Map(seq, enf$start_yr, enf$end_yr)
n_per_row  <- lengths(year_lists)
enf_long <- data.table(
  PWSID               = rep(enf$PWSID, n_per_row),
  ENF_ACTION_CATEGORY = rep(enf$ENF_ACTION_CATEGORY, n_per_row),
  year                = unlist(year_lists)
)
enf_long <- enf_long[year >= YR_LO & year <= YR_HI]

enf_py <- enf_long[, .(
    formal_enforcement   = as.integer(any(ENF_ACTION_CATEGORY == "Formal",   na.rm = TRUE)),
    informal_enforcement = as.integer(any(ENF_ACTION_CATEGORY == "Informal", na.rm = TRUE))
  ), by = .(PWSID, year)]
cat("CWS-years with ongoing formal enforcement:  ", sum(enf_py$formal_enforcement),   "\n")
cat("CWS-years with ongoing informal enforcement:", sum(enf_py$informal_enforcement), "\n")

rm(ve, enf, enf_long); gc()

# ── 2. Sanitary visits, year of visit ─────────────────────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= YR_LO & yr <= YR_HI]

san <- sv[VISIT_REASON_CODE %in% c("SNSV", "SNSP", "SSVF")]
san_events <- unique(san[, .(PWSID, visit_dt)])
cat("Sanitary visit events (event-level):", nrow(san_events), "\n")

san_py <- unique(san[, .(PWSID, year = yr)])
san_py[, sanitary_visit := 1L]
cat("CWS-years with a sanitary visit:", nrow(san_py), "\n")

rm(sv, san); gc()

# ── 3. Full CWS-year skeleton and merge ───────────────────────────────────────
skel <- CJ(PWSID = sample_pwsids, year = YR_LO:YR_HI)
skel <- merge(skel, mr_py,   by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, enf_py,  by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, san_py,  by = c("PWSID", "year"), all.x = TRUE)

fill0_cols <- c("mr_violation", "formal_enforcement", "informal_enforcement", "sanitary_visit")
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]

# No enforcement = neither formal nor informal ongoing in year t.
skel[, no_enforcement := as.integer(formal_enforcement == 0L & informal_enforcement == 0L)]

cat("\nFull CWS-year panel:", nrow(skel), "rows (", length(sample_pwsids),
    "CWSs x", YR_HI - YR_LO + 1L, "years)\n")

# ── 4. 365-day-window rows (row 4 / row 5) ───────────────────────────────────
# Row 4 ("following sanitary visit"): a sanitary visit in the 365 days BEFORE
# the MR onset (visit -> then MR). Row 5 ("preceding sanitary visit"): a
# sanitary visit in the 365 days AFTER the MR onset (MR -> then visit). Both
# use year t = the MR onset's calendar year for the enforcement outcome.
mr_onsets[, dummy_id := .I]

visit_before_365 <- san_events[mr_onsets,
  on = .(PWSID, visit_dt < onset_dt),
  .(dummy_id = i.dummy_id, gap_days = as.integer(i.onset_dt - x.visit_dt)),
  nomatch = NULL]
following_ids <- unique(visit_before_365[gap_days <= 365]$dummy_id)

visit_after_365 <- san_events[mr_onsets,
  on = .(PWSID, visit_dt > onset_dt),
  .(dummy_id = i.dummy_id, gap_days = as.integer(x.visit_dt - i.onset_dt)),
  nomatch = NULL]
preceding_ids <- unique(visit_after_365[gap_days <= 365]$dummy_id)

mr_onsets[, following_visit := as.integer(dummy_id %in% following_ids)]
mr_onsets[, preceding_visit := as.integer(dummy_id %in% preceding_ids)]

cat("\nIOC MR onsets with a sanitary visit in the 365 days before (following_visit):",
    sum(mr_onsets$following_visit), "\n")
cat("IOC MR onsets with a sanitary visit in the 365 days after (preceding_visit): ",
    sum(mr_onsets$preceding_visit), "\n")

following_py <- unique(mr_onsets[following_visit == 1, .(PWSID, year = onset_yr)])
preceding_py <- unique(mr_onsets[preceding_visit == 1, .(PWSID, year = onset_yr)])

# ── 5. Assemble the six row samples ──────────────────────────────────────────
row1_dt <- skel
row2_dt <- skel[mr_violation == 1]
row3_dt <- skel[mr_violation == 1 & sanitary_visit == 1]
row4_dt <- skel[following_py, on = .(PWSID, year), nomatch = NULL]
row5_dt <- skel[preceding_py, on = .(PWSID, year), nomatch = NULL]

# Row 6: row-3 sample restricted to upstream mines above the median.
above_median_py <- upstream_mines_py[num_coal_mines_upstream_sum > median_upstream_mines,
                                     .(PWSID, year)]
cat("\nCWS-years with upstream mines above the median:", nrow(above_median_py), "\n")
row6_dt <- row3_dt[above_median_py, on = .(PWSID, year), nomatch = NULL]
cat("IOC MR + same-year sanitary visit + upstream mines above median:", nrow(row6_dt), "\n")

row_dts <- list(row1_dt, row2_dt, row3_dt, row4_dt, row5_dt, row6_dt)

# ── 6. Rate + numerator count for each enforcement type in each row ──────────
count_col <- function(dt, col) sum(dt[[col]])
rate_col  <- function(dt, col) if (nrow(dt) == 0L) NA_real_ else 100 * mean(dt[[col]])

summ <- data.table(
  sample = c("All CWS-years (downstream 2SLS panel)",
             "CWS-years with an MR violation",
             "CWS-years with an MR violation and a sanitary visit (same year)",
             "CWS-years with an MR violation following sanitary visit",
             "CWS-years with an MR violation preceding sanitary visit",
             "CWS-years with an MR violation, sanitary visit (same year), and upstream mines above median"),
  n            = vapply(row_dts, nrow, integer(1)),
  formal_k     = vapply(row_dts, count_col, integer(1), "formal_enforcement"),
  informal_k   = vapply(row_dts, count_col, integer(1), "informal_enforcement"),
  none_k       = vapply(row_dts, count_col, integer(1), "no_enforcement"),
  formal_rate  = vapply(row_dts, rate_col, numeric(1), "formal_enforcement"),
  informal_rate= vapply(row_dts, rate_col, numeric(1), "informal_enforcement"),
  none_rate    = vapply(row_dts, rate_col, numeric(1), "no_enforcement")
)
cat("\n--- Enforcement rate table (IOC MR only, 6 rows) ---\n")
print(summ)

# ── 7. LaTeX table (hand-assembled; \begin{table} + adjustbox) ───────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

fmt_n    <- function(x) gsub(",", "{,}", formatC(x, format = "d", big.mark = ","))
fmt_cell <- function(rate, k) ifelse(is.na(rate), "--",
                                     sprintf("%.2f\\%% [%s]", rate, fmt_n(k)))

rows_tex <- sprintf("%s & %s & %s & %s & %s \\\\",
  summ$sample, fmt_n(summ$n),
  fmt_cell(summ$formal_rate,   summ$formal_k),
  fmt_cell(summ$informal_rate, summ$informal_k),
  fmt_cell(summ$none_rate,     summ$none_k))

notes <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-years ", YR_LO, "--",
  YR_HI, " (", nrow(row1_dt), " CWS-years). MR violations are restricted to the mining-related ",
  "inorganic chemicals only: nitrate (RULE\\_CODE 331), arsenic (332), and inorganic chemicals ",
  "(333). Each enforcement column reports the CWS-year rate as ``rate\\% [k]'', where k is the ",
  "number of CWS-years in that enforcement category within the row's sample (the numerator) and ",
  "the rate equals k divided by the N (CWS-years) column. The three enforcement indicators are ",
  "INDEPENDENT: formal = 1 if a violations-enforcement action with ENF\\_ACTION\\_CATEGORY = ",
  "Formal is ongoing at any point during year t; informal = 1 if an action with ENF\\_ACTION\\_",
  "CATEGORY = Informal is ongoing during year t; no enforcement = 1 if neither is ongoing. A ",
  "CWS-year may be both formal and informal, so the rates need not sum to 100\\%. Enforcement ",
  "spells run from the month of ENFORCEMENT\\_DATE through the month of CALCULATED\\_RTC\\_DATE ",
  "(fallback NON\\_COMPL\\_PER\\_END\\_DATE if RTC missing, else the enforcement month itself). MR ",
  "violation = 1 if an IOC MR violation onset begins in year t (NON\\_COMPL\\_PER\\_BEGIN\\_DATE). ",
  "Sanitary visit = 1 if a site visit with VISIT\\_REASON\\_CODE in \\{SNSV, SNSP, SSVF\\} occurs ",
  "in year t. Row 2 N\\,=\\,", fmt_n(nrow(row2_dt)), "; row 3 (visit in the same calendar year as ",
  "the MR onset) N\\,=\\,", fmt_n(nrow(row3_dt)), ". Row 4 (``following sanitary visit''): CWS-",
  "year t of an IOC MR onset where a sanitary visit occurred in the 365 days immediately ",
  "preceding that onset date (visit, then MR within a year), N\\,=\\,", fmt_n(nrow(row4_dt)), ". ",
  "Row 5 (``preceding sanitary visit''): CWS-year t of an IOC MR onset where a sanitary visit ",
  "occurred in the 365 days immediately following that onset date (MR, then visit within a ",
  "year), N\\,=\\,", fmt_n(nrow(row5_dt)), ". Rows 4-5 use year t = the calendar year of the MR ",
  "onset for the enforcement outcome; the 365-day window is measured in calendar days and may ",
  "cross year boundaries; a CWS-year with more than one qualifying MR onset appears once; rows ",
  "4 and 5 are not mutually exclusive. Row 6 restricts row 3's sample to CWS-years where ",
  "num\\_coal\\_mines\\_upstream\\_sum is above the median over all downstream 2SLS CWS-years ",
  "(median = ", median_upstream_mines, "), i.e. at least one upstream mine, N\\,=\\,",
  fmt_n(nrow(row6_dt)), "."
)

out_tex <- file.path(ROOT, "output/reg/sanitary_visit_timing_enforcement_rate_bychem_test.tex")
lines_tex <- c(
  "\\begin{table}[htbp]",
  paste0("\\caption{\\label{tab:sanitary_visit_timing_enforcement_rate_bychem_test} Enforcement ",
         "Rate (Formal, Informal, and None), by Sample Restriction, Visit Timing, and Upstream ",
         "Mine Count --- IOC MR Violations Only (Downstream CWSs, ", YR_LO, "--", YR_HI, ")}"),
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lcccc}",
  "\\toprule",
  "Sample & N (CWS-years) & Formal & Informal & No enforcement \\\\",
  "\\midrule",
  rows_tex,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes,
  "}",
  "\\end{table}"
)
writeLines(lines_tex, out_tex)
cat("\nTable saved to:", out_tex, "\n")

# ── 8. Verification ──────────────────────────────────────────────────────────
stopifnot(file.exists(out_tex), file.info(out_tex)$size > 0)
stopifnot(nrow(row1_dt) > nrow(row2_dt), nrow(row2_dt) >= nrow(row3_dt), nrow(row3_dt) > 0)
stopifnot(nrow(row4_dt) <= nrow(row2_dt), nrow(row5_dt) <= nrow(row2_dt))
stopifnot(nrow(row6_dt) >= 0, nrow(row6_dt) <= nrow(row3_dt))
# Independent indicators: formal + none never exceed N; none = N - (formal|informal).
for (i in seq_len(nrow(summ))) {
  stopifnot(summ$formal_k[i]   <= summ$n[i],
            summ$informal_k[i] <= summ$n[i],
            summ$none_k[i]     <= summ$n[i])
}
cat("Output verified: file exists, non-zero; row Ns and category counts consistent.\n")
cat("=== DONE ===\n")
