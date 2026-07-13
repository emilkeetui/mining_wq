# ============================================================
# Script: sanitary_visit_formal_enforcement_rate_syr2_above_mean.r
# Purpose: Test version of sanitary_visit_timing_formal_enforcement_rate.tex
#          with a 6th row: formal enforcement rate among CWS-years with an
#          MR violation onset AND a same-year sanitary visit AND at least one
#          SYR2 reading among arsenic, chromium, barium, nitrate, and
#          selenium ABOVE its respective sample mean that CWS-year (any of
#          the 5 tested chemicals qualifying, not all).
#          Mean thresholds are the fixed published values from
#          output/sum/6yr_huc02fe_inorg_val_sumstats_ravalli_2005.tex
#          (Arsenic 0.0029, Nitrate 0.7520, Barium 0.0748, Chromium 0.0059,
#          Selenium 0.0048 mg/L), not recomputed here. Rows 1-5 reproduce
#          sanitary_visit_formal_enforcement_rate.r exactly for comparison.
#          Mirror of sanitary_visit_formal_enforcement_rate_syr2_below_mean.r
#          with the row-6 comparison direction flipped.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/sum/sanitary_visit_formal_enforcement_rate_syr2_above_mean.tex
# Author: EK  Date: 2026-07-13
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

YR_LO <- 1985L
YR_HI <- 2005L

# Fixed thresholds from output/sum/6yr_huc02fe_inorg_val_sumstats_ravalli_2005.tex
# (mean VALUE, mg/L, over that table's regression-conditioned sample).
SYR2_MEANS <- c(
  arsenic  = 0.0029,
  nitrate  = 0.7520,
  barium   = 0.0748,
  chromium = 0.0059,
  selenium = 0.0048
)

# ── 0. Sample: strictly-downstream CWSs ───────────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"),
    col_select = c("PWSID", "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0
sample_pwsids   <- unique(panel$PWSID[downstream_mask])
cat("Downstream CWSs in sample:", length(sample_pwsids), "\n")

# ── 1. Violations + enforcement ───────────────────────────────────────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE",
                 "VIOLATION_CATEGORY_CODE", "ENFORCEMENT_ID", "ENFORCEMENT_DATE",
                 "ENF_ACTION_CATEGORY", "CALCULATED_RTC_DATE")))
ve <- ve[PWSID %in% sample_pwsids]

# ── 1a. MR violation onsets: dedupe on VIOLATION_ID, year of onset ───────────
onsets <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE, VIOLATION_CATEGORY_CODE)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= YR_LO & onset_yr <= YR_HI]

mr_onsets <- onsets[VIOLATION_CATEGORY_CODE == "MR", .(PWSID, VIOLATION_ID, onset_dt, onset_yr)]
cat("MR violation onsets (event-level):", nrow(mr_onsets), "\n")

mr_py <- unique(mr_onsets[, .(PWSID, year = onset_yr, mr_violation = 1L)])
cat("CWS-years with an MR violation onset:", nrow(mr_py), "\n")

# ── 1b. Enforcement spans -> formal enforcement, expanded to CWS-year ────────
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

formal_starts <- unique(enf[ENF_ACTION_CATEGORY == "Formal", .(PWSID, enf_dt)])
cat("Formal enforcement spell starts (event-level):", nrow(formal_starts), "\n")

year_lists <- Map(seq, enf$start_yr, enf$end_yr)
n_per_row  <- lengths(year_lists)
enf_long <- data.table(
  PWSID               = rep(enf$PWSID, n_per_row),
  ENF_ACTION_CATEGORY = rep(enf$ENF_ACTION_CATEGORY, n_per_row),
  year                = unlist(year_lists)
)
enf_long <- enf_long[year >= YR_LO & year <= YR_HI]

enf_formal_py <- enf_long[, .(formal_enforcement = as.integer(any(ENF_ACTION_CATEGORY == "Formal", na.rm = TRUE))),
                           by = .(PWSID, year)]
cat("CWS-years with ongoing formal enforcement:", sum(enf_formal_py$formal_enforcement), "\n")

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
skel <- merge(skel, mr_py,           by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, enf_formal_py,   by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, san_py,          by = c("PWSID", "year"), all.x = TRUE)

fill0_cols <- c("mr_violation", "formal_enforcement", "sanitary_visit")
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]

cat("\nFull CWS-year panel:", nrow(skel), "rows (", length(sample_pwsids),
    "CWSs x", YR_HI - YR_LO + 1L, "years)\n")

# ── 4. Rows 1-3: rate of formal enforcement across nested samples ───────────
row1_dt <- skel
row2_dt <- skel[mr_violation == 1]
row3_dt <- skel[mr_violation == 1 & sanitary_visit == 1]

rate <- function(dt) 100 * mean(dt$formal_enforcement)

# ── 4b. Rows 4-5: 365-day-window MR onset <-> sanitary visit ordering ───────
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

following_py <- unique(mr_onsets[following_visit == 1, .(PWSID, year = onset_yr)])
preceding_py <- unique(mr_onsets[preceding_visit == 1, .(PWSID, year = onset_yr)])

row4_dt <- skel[following_py, on = .(PWSID, year), nomatch = NULL]
row5_dt <- skel[preceding_py, on = .(PWSID, year), nomatch = NULL]

# ── 4c. Row 6: row-3 sample + SYR2 readings above chemical means ────────────
# For each CWS-year in row3_dt (MR violation + same-year sanitary visit),
# check every SYR2 reading of the 5 target chemicals in that CWS-year and
# require at least one to be above its fixed published mean (SYR2_MEANS). A
# CWS-year qualifies if any of the chemicals it was tested for that year
# came in above its mean (not all 5 required, and not all tested chemicals
# required to be above); CWS-years with zero SYR2 readings for any of the 5
# chemicals that year do not qualify.
syr2 <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"),
  col_select = c("PWSID", "YEAR", "CHEMID_name", "VALUE")))
syr2 <- syr2[PWSID %in% sample_pwsids & CHEMID_name %in% names(SYR2_MEANS) & !is.na(VALUE)]
setnames(syr2, "YEAR", "year")
cat("\nSYR2 readings for the 5 target chemicals (downstream sample):", nrow(syr2), "\n")

syr2[, chem_mean := SYR2_MEANS[CHEMID_name]]
syr2[, above_mean := VALUE > chem_mean]

# CWS-year qualifies iff at least one tested chemical that year is above its
# mean (any() over the readings present; a CWS-year with 0 rows for these
# chemicals is absent from above_mean_py and therefore does not qualify).
above_mean_py <- syr2[, .(any_above_mean = as.integer(any(above_mean))), by = .(PWSID, year)]
above_mean_py <- above_mean_py[any_above_mean == 1, .(PWSID, year)]
cat("CWS-years where any tested SYR2 chemical (of the 5) is above its mean:",
    nrow(above_mean_py), "\n")

row6_dt <- row3_dt[above_mean_py, on = .(PWSID, year), nomatch = NULL]
cat("CWS-years with MR violation + same-year sanitary visit + SYR2 above mean:",
    nrow(row6_dt), "\n")

# ── 5. Combined 6-row table ──────────────────────────────────────────────────
rows6 <- data.table(
  sample = c("All CWS-years (downstream 2SLS panel)",
             "CWS-years with an MR violation",
             "CWS-years with an MR violation and a sanitary visit (same year)",
             "CWS-years with an MR violation following sanitary visit",
             "CWS-years with an MR violation preceding sanitary visit",
             "CWS-years with an MR violation, sanitary visit (same year), and SYR2 above mean"),
  n    = c(nrow(row1_dt), nrow(row2_dt), nrow(row3_dt), nrow(row4_dt), nrow(row5_dt), nrow(row6_dt)),
  rate = c(rate(row1_dt), rate(row2_dt), rate(row3_dt), rate(row4_dt), rate(row5_dt), rate(row6_dt))
)
cat("\n--- Formal enforcement rate table (6 rows, test version, above-mean) ---\n")
print(rows6)

dir.create(file.path(ROOT, "output/sum"), showWarnings = FALSE, recursive = TRUE)

fmt_n   <- function(x) gsub(",", "{,}", formatC(x, format = "d", big.mark = ","))
fmt_pct <- function(x) sprintf("%.2f", x)

rows6_tex <- sprintf("%s & %s & %s\\%% \\\\", rows6$sample, fmt_n(rows6$n), fmt_pct(rows6$rate))

mean_str <- paste(sprintf("%s = %.4f mg/L", names(SYR2_MEANS), SYR2_MEANS), collapse = "; ")

notes_6row <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-years ", YR_LO, "--",
  YR_HI, " (", nrow(row1_dt), " CWS-years). Rows 1-5 reproduce sanitary\\_visit\\_formal\\_",
  "enforcement\\_rate.r exactly. Formal enforcement = 1 if a violations-enforcement action ",
  "with ENF\\_ACTION\\_CATEGORY = Formal is ongoing at any point during the calendar year t. ",
  "MR violation = 1 if a violation onset with VIOLATION\\_CATEGORY\\_CODE = MR begins in year t. ",
  "Sanitary visit = 1 if a site visit with VISIT\\_REASON\\_CODE in \\{SNSV, SNSP, SSVF\\} occurs ",
  "in year t. Row 4 (``following sanitary visit''): sanitary visit in the 365 days immediately ",
  "preceding the MR onset date. Row 5 (``preceding sanitary visit''): sanitary visit in the 365 ",
  "days immediately following the MR onset date; rows 4-5 use year t = the MR onset's calendar ",
  "year and are not mutually exclusive. Row 6 (test row): restricts row 3's sample (MR ",
  "violation and same-year sanitary visit) to CWS-years where at least one SYR2 (6-Year ",
  "Review) reading of arsenic, nitrate, barium, chromium, or selenium taken that year is above ",
  "that chemical's mean, using the fixed published means from Table~",
  "\\ref{tab:6yr_huc02fe_inorg_val_sumstats_ravalli_2005} (", mean_str, "); any one of the 5 ",
  "tested chemicals being above its mean qualifies the CWS-year (not all 5 required to be ",
  "tested or above), and CWS-years with no SYR2 reading of any of the 5 chemicals that year do ",
  "not qualify. Row Ns: row 2\\,=\\,", fmt_n(nrow(row2_dt)), "; row 3\\,=\\,", fmt_n(nrow(row3_dt)),
  "; row 4\\,=\\,", fmt_n(nrow(row4_dt)), "; row 5\\,=\\,", fmt_n(nrow(row5_dt)),
  "; row 6\\,=\\,", fmt_n(nrow(row6_dt)), "."
)

out_tex <- file.path(ROOT, "output/sum/sanitary_visit_formal_enforcement_rate_syr2_above_mean.tex")
lines_tex <- c(
  "\\begin{table}[htbp]",
  paste0("\\caption{\\label{tab:sanitary_visit_formal_enforcement_rate_syr2_above_mean} Formal ",
         "Enforcement Rate, by Sample Restriction, Visit Timing, and SYR2 Level (Downstream ",
         "CWSs, ", YR_LO, "--", YR_HI, ") -- Test Version, Above Mean}"),
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lcc}",
  "\\toprule",
  "Sample & N (CWS-years) & Formal enforcement rate \\\\",
  "\\midrule",
  rows6_tex,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_6row,
  "}",
  "\\end{table}"
)
writeLines(lines_tex, out_tex)
cat("\nTable saved to:", out_tex, "\n")

# ── 6. Verification ──────────────────────────────────────────────────────────
stopifnot(file.exists(out_tex), file.info(out_tex)$size > 0)
stopifnot(nrow(row1_dt) > nrow(row2_dt), nrow(row2_dt) >= nrow(row3_dt), nrow(row3_dt) > 0)
stopifnot(nrow(row4_dt) > 0, nrow(row5_dt) > 0)
stopifnot(nrow(row6_dt) >= 0, nrow(row6_dt) <= nrow(row3_dt))
cat("Output verified: file exists, non-zero; row 6 N <= row 3 N as required.\n")
cat("=== DONE ===\n")
