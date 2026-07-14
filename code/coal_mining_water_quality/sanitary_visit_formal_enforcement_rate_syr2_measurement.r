# ============================================================
# Script: sanitary_visit_formal_enforcement_rate_syr2_measurement.r
# Purpose: Formal enforcement rate table keyed on CWS-dates with an SYR2
#          measurement (unit = PWSID x sample_date), for the main 2SLS
#          downstream sample:
#          Row 1: all CWS-dates with an SYR2 measurement.
#          Row 2: + an MR violation whose non-compliance period covers
#                 the sample_date.
#          Row 3: + a sanitary visit in the same calendar year as the
#                 sample_date.
#          Row 4: + at least one SYR2 reading (of arsenic, nitrate,
#                 barium, chromium, selenium) in that same calendar year
#                 exceeding its fixed published mean from
#                 output/sum/6yr_huc02fe_inorg_val_sumstats_ravalli_2005.tex.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/sum/sanitary_visit_formal_enforcement_rate_syr2_measurement.tex
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

# ── 1. SYR2 measurement-level dates (all chemicals, not just the 5 target) ──
syr2_all <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"),
  col_select = c("PWSID", "CHEMID_name", "sample_date", "YEAR", "VALUE")))
syr2_all <- syr2_all[PWSID %in% sample_pwsids]
syr2_all[, sample_dt := as.Date(sample_date)]
syr2_all <- syr2_all[!is.na(sample_dt) & YEAR >= YR_LO & YEAR <= YR_HI]

cws_dates <- unique(syr2_all[, .(PWSID, sample_dt, year = YEAR)])
cat("CWS-dates with an SYR2 measurement (downstream sample):", nrow(cws_dates), "\n")

# ── 2. Violations + enforcement ───────────────────────────────────────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE",
                 "VIOLATION_CATEGORY_CODE", "ENFORCEMENT_ID", "ENFORCEMENT_DATE",
                 "ENF_ACTION_CATEGORY", "CALCULATED_RTC_DATE")))
ve <- ve[PWSID %in% sample_pwsids]

# ── 2a. MR violation spans: [begin_dt, end_dt] (open-ended if end missing) ──
mr <- unique(ve[VIOLATION_CATEGORY_CODE == "MR",
  .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE, NON_COMPL_PER_END_DATE)])
mr[, begin_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
mr[, end_dt   := as.Date(NON_COMPL_PER_END_DATE,   "%m/%d/%Y")]
mr <- mr[!is.na(begin_dt)]
mr[, end_dt := fifelse(is.na(end_dt), as.Date(paste0(YR_HI, "-12-31")), end_dt)]
cat("MR violation spans (event-level):", nrow(mr), "\n")

# ── 2b. Enforcement spans -> formal enforcement, expanded to CWS-year ────────
enf <- ve[!is.na(ENFORCEMENT_ID) & !is.na(ENFORCEMENT_DATE)]
enf[, enf_dt := as.Date(ENFORCEMENT_DATE, "%m/%d/%Y")]
enf <- enf[!is.na(enf_dt)]
enf[, enf_yr := as.integer(format(enf_dt, "%Y"))]
enf <- enf[enf_yr >= YR_LO & enf_yr <= YR_HI]
enf[, rtc_dt  := as.Date(CALCULATED_RTC_DATE,    "%m/%d/%Y")]
enf[, ncpe_dt := as.Date(NON_COMPL_PER_END_DATE, "%m/%d/%Y")]
enf[, end_dt2 := fifelse(!is.na(rtc_dt), rtc_dt, fifelse(!is.na(ncpe_dt), ncpe_dt, enf_dt))]
enf[, start_yr := as.integer(format(enf_dt, "%Y"))]
enf[, end_yr   := pmax(as.integer(format(end_dt2, "%Y")), start_yr)]
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

enf_formal_py <- enf_long[, .(formal_enforcement = as.integer(any(ENF_ACTION_CATEGORY == "Formal", na.rm = TRUE))),
                           by = .(PWSID, year)]
cat("CWS-years with ongoing formal enforcement:", sum(enf_formal_py$formal_enforcement), "\n")

rm(ve, enf, enf_long); gc()

# ── 3. Sanitary visits, year of visit ─────────────────────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= YR_LO & yr <= YR_HI]

san <- sv[VISIT_REASON_CODE %in% c("SNSV", "SNSP", "SSVF")]
san_py <- unique(san[, .(PWSID, year = yr)])
san_py[, sanitary_visit := 1L]
cat("CWS-years with a sanitary visit:", nrow(san_py), "\n")

rm(sv, san); gc()

# ── 4. Build CWS-date level dataset with all flags merged in ────────────────
dat <- copy(cws_dates)
dat <- merge(dat, enf_formal_py, by = c("PWSID", "year"), all.x = TRUE)
dat <- merge(dat, san_py,        by = c("PWSID", "year"), all.x = TRUE)
dat[is.na(formal_enforcement), formal_enforcement := 0L]
dat[is.na(sanitary_visit),     sanitary_visit     := 0L]

# MR violation covering the sample_date: non-equi join on span containment
mr_hit <- mr[dat, on = .(PWSID, begin_dt <= sample_dt, end_dt >= sample_dt),
             .(PWSID, sample_dt = i.sample_dt), nomatch = NULL]
mr_hit <- unique(mr_hit)
mr_hit[, mr_violation := 1L]
dat <- merge(dat, mr_hit, by = c("PWSID", "sample_dt"), all.x = TRUE)
dat[is.na(mr_violation), mr_violation := 0L]

cat("\nCWS-dates with an MR violation covering the date:", sum(dat$mr_violation), "\n")
cat("CWS-dates with MR violation + same-year sanitary visit:",
    dat[mr_violation == 1 & sanitary_visit == 1, .N], "\n")

# ── 5. Row 4: any of the 5 target chemicals above its mean, same CWS-year ────
syr2_5 <- syr2_all[CHEMID_name %in% names(SYR2_MEANS) & !is.na(VALUE)]
syr2_5[, chem_mean := SYR2_MEANS[CHEMID_name]]
syr2_5[, above_mean := VALUE > chem_mean]

above_mean_py <- syr2_5[, .(any_above_mean = as.integer(any(above_mean))), by = .(PWSID, YEAR)]
above_mean_py <- above_mean_py[any_above_mean == 1, .(PWSID, year = YEAR)]
cat("CWS-years with >=1 of the 5 target chemicals above its mean:", nrow(above_mean_py), "\n")

# ── 6. Rows 1-4: nested samples of CWS-dates ─────────────────────────────────
row1_dt <- dat
row2_dt <- dat[mr_violation == 1]
row3_dt <- dat[mr_violation == 1 & sanitary_visit == 1]
row4_dt <- row3_dt[above_mean_py, on = .(PWSID, year), nomatch = NULL]

rate <- function(dt) 100 * mean(dt$formal_enforcement)

rows4 <- data.table(
  sample = c("All CWS-dates with an SYR2 measurement (downstream 2SLS sample)",
             "CWS-dates with an MR violation covering that date",
             "CWS-dates with an MR violation and a sanitary visit (same year)",
             "CWS-dates with an MR violation, sanitary visit (same year), and $\\geq$1 SYR2 reading above mean"),
  n    = c(nrow(row1_dt), nrow(row2_dt), nrow(row3_dt), nrow(row4_dt)),
  rate = c(rate(row1_dt), rate(row2_dt), rate(row3_dt), rate(row4_dt))
)
cat("\n--- Formal enforcement rate table (CWS-date level, 4 rows) ---\n")
print(rows4)

dir.create(file.path(ROOT, "output/sum"), showWarnings = FALSE, recursive = TRUE)

fmt_n   <- function(x) gsub(",", "{,}", formatC(x, format = "d", big.mark = ","))
fmt_pct <- function(x) sprintf("%.2f", x)

rows4_tex <- sprintf("%s & %s & %s\\%% \\\\", rows4$sample, fmt_n(rows4$n), fmt_pct(rows4$rate))

mean_str <- paste(sprintf("%s = %.4f mg/L", names(SYR2_MEANS), SYR2_MEANS), collapse = "; ")

notes_4row <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-dates with an SYR2 ",
  "(6-Year Review) measurement, ", YR_LO, "--", YR_HI, " (", nrow(row1_dt), " CWS-dates). Unit ",
  "of observation is PWSID x sample\\_date (not PWSID x year). Formal enforcement = 1 if a ",
  "violations-enforcement action with ENF\\_ACTION\\_CATEGORY = Formal is ongoing at any point ",
  "during the calendar year of the sample\\_date. MR violation = 1 if an MR violation's ",
  "non-compliance period (NON\\_COMPL\\_PER\\_BEGIN\\_DATE to NON\\_COMPL\\_PER\\_END\\_DATE, or ",
  "open-ended through ", YR_HI, " if no end date) covers the sample\\_date. Sanitary visit = 1 ",
  "if a site visit with VISIT\\_REASON\\_CODE in \\{SNSV, SNSP, SSVF\\} occurs in the same ",
  "calendar year as the sample\\_date. Row 4 restricts row 3's sample to CWS-dates where, in ",
  "that same calendar year, at least one SYR2 reading of arsenic, nitrate, barium, chromium, or ",
  "selenium exceeds that chemical's fixed published mean from Table~",
  "\\ref{tab:6yr_huc02fe_inorg_val_sumstats_ravalli_2005} (", mean_str, "); only one of the 5 ",
  "chemicals need exceed its mean to qualify. Row Ns: row 2\\,=\\,", fmt_n(nrow(row2_dt)),
  "; row 3\\,=\\,", fmt_n(nrow(row3_dt)), "; row 4\\,=\\,", fmt_n(nrow(row4_dt)), "."
)

out_tex <- file.path(ROOT, "output/sum/sanitary_visit_formal_enforcement_rate_syr2_measurement.tex")
lines_tex <- c(
  "\\begin{table}[htbp]",
  paste0("\\caption{\\label{tab:sanitary_visit_formal_enforcement_rate_syr2_measurement} Formal ",
         "Enforcement Rate, by Sample Restriction (CWS-Date Level, Downstream CWSs, ",
         YR_LO, "--", YR_HI, ")}"),
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lcc}",
  "\\toprule",
  "Sample & N (CWS-dates) & Formal enforcement rate \\\\",
  "\\midrule",
  rows4_tex,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_4row,
  "}",
  "\\end{table}"
)
writeLines(lines_tex, out_tex)
cat("\nTable saved to:", out_tex, "\n")

# ── 7. Verification ──────────────────────────────────────────────────────────
stopifnot(file.exists(out_tex), file.info(out_tex)$size > 0)
stopifnot(nrow(row1_dt) > nrow(row2_dt), nrow(row2_dt) >= nrow(row3_dt))
stopifnot(nrow(row4_dt) <= nrow(row3_dt))
cat("Output verified: file exists, non-zero; nested row Ns are monotonic as required.\n")
cat("=== DONE ===\n")
