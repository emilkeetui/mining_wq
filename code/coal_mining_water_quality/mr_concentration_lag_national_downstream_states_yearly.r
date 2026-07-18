# ============================================================
# Script: mr_concentration_lag_national_downstream_states_yearly.r
# Purpose: CWS-year version of mr_concentration_lag_national_downstream_
#          states.r, restricted to nitrate. Mirrors the panel construction
#          in syr2_test_mr_violation_bychem_iterative.r (binary lead/lag
#          window indicators built around test/reading dates) but uses
#          near-MCL / concentration-z-score readings instead of test-
#          occurrence, at 6-month AND 12-month lead/lag horizons, collapsed
#          to CWS-year grain (reduced from CWS-month: at national scale,
#          53,335 CWSs x 108 months x 2 horizons made the CWS-month etable
#          step prohibitively slow; CWS-year cuts row count ~12x).
#          Lead/lag windows are still computed at day-level precision from
#          the underlying reading dates, then rolled up: a CWS-year's
#          lead6/lead12 indicator is 1 if ANY month in that year had a
#          reading in its own 6/12-month-forward window (lag: backward).
#            near_mcl_lead6/lead12   = 1 if any reading at 50-100% of the
#                                       MCL occurred in the 6/12 months
#                                       AFTER some month in that CWS-year
#            near_mcl_lag6/lag12     = 1 if any such reading occurred in
#                                       the 6/12 months BEFORE
#            mean_conc_z_lead6/lag6/... = mean of the PWSID-YEAR z-scored
#                                       concentration among readings in
#                                       that window (0 if no reading)
#          Dependent variable: 1 if a nitrate MR violation onset occurs in
#          that CWS-year.
#          Col 1: 6-month windows,  no FE
#          Col 2: 6-month windows,  CWS + year FE
#          Col 3: 12-month windows, no FE
#          Col 4: 12-month windows, CWS + year FE
# Inputs:  clean_data/mr_concentration_lag_national_nitrate.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: output/reg/mr_concentration_lag_national_downstream_states_yearly.tex
# Author: EK  Date: 2026-07-16
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)

ROOT <- "Z:/ek559/mining_wq"

# States with >=1 CWS in prod_vio_sulfur.parquet under
# minehuc_downstream_of_mine==1 & minehuc_mine==0, year 1985-2005
# (matches mr_concentration_lag_national_downstream_states.r).
downstream_states <- c("AL", "CA", "CO", "FL", "GA", "IL", "KS", "KY", "LA", "MD", "NC", "NJ",
                        "NY", "OH", "OR", "PA", "SC", "TN", "UT", "VA", "WA", "WV")

month_idx_of <- function(d) {
  yr <- as.integer(format(d, "%Y"))
  mo <- as.integer(format(d, "%m"))
  (yr - 1985L) * 12L + (mo - 1L) + 1L
}
year_of_month_idx <- function(m) 1985L + ((m - 1L) %/% 12L)

# ── 1. SYR2 nitrate readings, restricted to downstream-2SLS-sample states ────
syr2 <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/mr_concentration_lag_national_nitrate.parquet"),
  col_select = c("PWSID", "sample_date", "YEAR", "VALUE", "near_mcl")))

syr2[, state := substr(PWSID, 1, 2)]
syr2 <- syr2[state %in% downstream_states]
cat("SYR2 nitrate readings, downstream-2SLS-sample states:", nrow(syr2),
    "| unique PWSID:", uniqueN(syr2$PWSID), "\n")

syr2[, sample_dt := as.Date(sample_date)]
syr2 <- syr2[!is.na(sample_dt)]
syr2[, yr := as.integer(format(sample_dt, "%Y"))]
syr2 <- syr2[yr >= 1985 & yr <= 2005]
syr2[, month_idx := month_idx_of(sample_dt)]

sample_pwsids <- unique(syr2$PWSID)
cat("CWSs in sample:", length(sample_pwsids), "\n")

n_months <- month_idx_of(as.Date("2005-12-01"))
year_lo  <- 1997L
year_hi  <- 2005L

# mean_concentration = PWSID-YEAR mean VALUE, z-scored across the full
# retained sample (matches mr_concentration_lag_national_downstream_states.r).
syr2[, mean_concentration := mean(VALUE), by = .(PWSID, YEAR)]
syr2[, mean_conc_z := as.numeric(scale(mean_concentration))]

n_near_mcl <- sum(syr2$near_mcl == 1, na.rm = TRUE)
cat("near_mcl==1 readings:", n_near_mcl, "\n")

# ── 2. Nitrate MR violation onsets (CWS-year) ─────────────────────────────────
ve <- as.data.table(arrow::read_parquet(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet",
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE", "CONTAMINANT_CODE")))
ve <- ve[PWSID %in% sample_pwsids]
contam_str <- trimws(as.character(ve$CONTAMINANT_CODE))
ve <- ve[VIOLATION_CATEGORY_CODE == "MR" & contam_str %in% c("1040", "1040.0")]

onsets <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= year_lo & onset_yr <= year_hi]

mr_py <- unique(onsets[, .(PWSID, year = onset_yr)])
mr_py[, mr_violation := 1L]
cat("CWS-years with a nitrate MR violation onset:", nrow(mr_py), "\n")

rm(ve); gc()

# ── 3. Build lead/lag window indicators + window-mean z-score, per horizon,
#       at CWS-month grain first (day-level precision), then roll up to
#       CWS-year (a year's indicator = 1 if any month in that year has the
#       window indicator = 1; z-score = mean across that year's months) ────
build_windows_yearly <- function(h) {
  # One row per PWSID x reading-month, collapsing multiple same-month readings
  # to the presence of a near-MCL reading and the mean z-score that month.
  d <- syr2[, .(near_mcl = as.integer(any(near_mcl == 1)),
                mean_conc_z = mean(mean_conc_z, na.rm = TRUE)),
            by = .(PWSID, reading_month = month_idx)]

  # Lead window: reading occurs in the h months AFTER the CWS-month, i.e.
  # a CWS-month at reading_month - k (k = 1..h) sees this reading as a lead.
  lead_months <- d[, .(month_idx = reading_month - seq_len(h)), by = .(PWSID, reading_month)]
  lead_long   <- merge(lead_months, d, by = c("PWSID", "reading_month"))

  # Lag window: reading occurs in the h months BEFORE the CWS-month, i.e.
  # a CWS-month at reading_month + k (k = 1..h) sees this reading as a lag.
  lag_months <- d[, .(month_idx = reading_month + seq_len(h)), by = .(PWSID, reading_month)]
  lag_long   <- merge(lag_months, d, by = c("PWSID", "reading_month"))

  lead_long <- lead_long[month_idx >= 1L & month_idx <= n_months]
  lag_long  <- lag_long[month_idx  >= 1L & month_idx <= n_months]

  lead_pm <- lead_long[, .(near_mcl_lead   = as.integer(any(near_mcl == 1)),
                            mean_conc_z_lead = mean(mean_conc_z, na.rm = TRUE)),
                        by = .(PWSID, month_idx)]
  lag_pm  <- lag_long[,  .(near_mcl_lag    = as.integer(any(near_mcl == 1)),
                            mean_conc_z_lag  = mean(mean_conc_z, na.rm = TRUE)),
                        by = .(PWSID, month_idx)]

  win_pm <- merge(lead_pm, lag_pm, by = c("PWSID", "month_idx"), all = TRUE)
  win_pm[is.na(near_mcl_lead),    near_mcl_lead    := 0L]
  win_pm[is.na(near_mcl_lag),     near_mcl_lag     := 0L]
  win_pm[is.na(mean_conc_z_lead), mean_conc_z_lead := 0]
  win_pm[is.na(mean_conc_z_lag),  mean_conc_z_lag  := 0]

  # Roll up CWS-month -> CWS-year.
  win_pm[, year := year_of_month_idx(month_idx)]
  win_py <- win_pm[, .(near_mcl_lead    = as.integer(any(near_mcl_lead == 1)),
                        near_mcl_lag     = as.integer(any(near_mcl_lag  == 1)),
                        mean_conc_z_lead = mean(mean_conc_z_lead),
                        mean_conc_z_lag  = mean(mean_conc_z_lag)),
                    by = .(PWSID, year)]

  setnames(win_py, c("near_mcl_lead", "near_mcl_lag", "mean_conc_z_lead", "mean_conc_z_lag"),
                    paste0(c("near_mcl_lead", "near_mcl_lag", "mean_conc_z_lead", "mean_conc_z_lag"), h))
  win_py
}

cat("Building 6-month lead/lag windows...\n")
win6  <- build_windows_yearly(6L)
cat("Building 12-month lead/lag windows...\n")
win12 <- build_windows_yearly(12L)

# ── 4. Build CWS-year skeleton and merge ──────────────────────────────────────
skel <- CJ(PWSID = sample_pwsids, year = seq(year_lo, year_hi))
skel <- merge(skel, mr_py, by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, win6,  by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, win12, by = c("PWSID", "year"), all.x = TRUE)
setorder(skel, PWSID, year)

win_cols  <- c("near_mcl_lead6", "near_mcl_lag6", "near_mcl_lead12", "near_mcl_lag12")
z_cols    <- c("mean_conc_z_lead6", "mean_conc_z_lag6", "mean_conc_z_lead12", "mean_conc_z_lag12")
fill0_cols <- c("mr_violation", win_cols, z_cols)
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]

cat("\nCWS-year panel:", nrow(skel), "rows (", length(sample_pwsids),
    "CWSs x", year_hi - year_lo + 1L, "years)\n")
cat("mr_violation mean:", round(mean(skel$mr_violation), 6), "\n")

# ── 5. Regressions ─────────────────────────────────────────────────────────────
run_spec_no_fe <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs))
  feols(fml, data = dt, cluster = ~PWSID)
}
run_spec <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs, " | PWSID + year"))
  feols(fml, data = dt, cluster = ~PWSID)
}

rhs_6mon  <- "near_mcl_lead6 + near_mcl_lag6 + mean_conc_z_lead6 + mean_conc_z_lag6"
rhs_12mon <- "near_mcl_lead12 + near_mcl_lag12 + mean_conc_z_lead12 + mean_conc_z_lag12"

m_6_no_fe  <- run_spec_no_fe("mr_violation", rhs_6mon,  skel)
m_6_fe     <- run_spec(      "mr_violation", rhs_6mon,  skel)
m_12_no_fe <- run_spec_no_fe("mr_violation", rhs_12mon, skel)
m_12_fe    <- run_spec(      "mr_violation", rhs_12mon, skel)

cat("\n--- Nitrate MR violation, 6-month windows, no FE ---\n");         print(summary(m_6_no_fe))
cat("\n--- Nitrate MR violation, 6-month windows, CWS+year FE ---\n");   print(summary(m_6_fe))
cat("\n--- Nitrate MR violation, 12-month windows, no FE ---\n");        print(summary(m_12_no_fe))
cat("\n--- Nitrate MR violation, 12-month windows, CWS+year FE ---\n");  print(summary(m_12_fe))

# ── 6. LaTeX table ─────────────────────────────────────────────────────────────
move_notes_below_adjustbox <- function(x) {
  x           <- paste(x, collapse = "\n")
  end_adj     <- "\\end{adjustbox}"
  par_rag     <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj,
            paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                   trimws(note_block), "}"),
            x, fixed = TRUE)
  x
}

dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

dict <- c(
  mr_violation        = "Nitrate MR violation onset in year t",
  near_mcl_lead6       = "Reading $>$50\\% MCL, lead (1, 6) months",
  near_mcl_lag6        = "Reading $>$50\\% MCL, lag (-6, -1) months",
  mean_conc_z_lead6    = "Mean concen. (z-score), lead (1, 6) months",
  mean_conc_z_lag6     = "Mean concen. (z-score), lag (-6, -1) months",
  near_mcl_lead12      = "Reading $>$50\\% MCL, lead (1, 12) months",
  near_mcl_lag12       = "Reading $>$50\\% MCL, lag (-12, -1) months",
  mean_conc_z_lead12   = "Mean concen. (z-score), lead (1, 12) months",
  mean_conc_z_lag12    = "Mean concen. (z-score), lag (-12, -1) months",
  PWSID               = "CWS",
  year                = "Year"
)

out_tex <- file.path(ROOT, "output/reg/mr_concentration_lag_national_downstream_states_yearly.tex")
note_main <- paste0(
  "Sample: national SYR2 nitrate sample restricted to states with at least one CWS in the ",
  "main downstream 2SLS sample (minehuc\\_downstream\\_of\\_mine==1 \\& minehuc\\_mine==0, ",
  "1985--2005), nitrate only (", length(sample_pwsids), " CWSs), CWS-years 1997 to 2005. ",
  "Outcome = 1 if a nitrate MR (monitoring/reporting) violation onset occurs in that CWS-",
  "year. Reading $>$50\\% MCL lead/lag = 1 if any SYR2 nitrate reading at 50--100\\% of ",
  "the MCL (the 40 CFR 141.23(d)(2) quarterly-monitoring trigger, n=", n_near_mcl,
  " readings) occurred in the 6 or 12 calendar months following (lead) or preceding (lag) ",
  "any month in that CWS-year; both are 0 outside any such window (built at CWS-month ",
  "grain from day-level reading dates, then rolled up to the CWS-year: the year indicator ",
  "is 1 if any of its 12 months has the monthly window indicator equal to 1). Mean concen. ",
  "(z-score) lead/lag = mean, across that CWS-year's months, of the mean PWSID-YEAR mean ",
  "concentration (z-scored across the sample) among readings in the same lead/lag window; ",
  "0 in months with no reading in that window. Columns (2) and (4) include CWS and year ",
  "fixed effects; columns (1) and (3) have no fixed effects. N=", nrow(skel),
  " in all columns. SEs clustered at the CWS (PWSID) level in all columns."
)

do.call(etable, c(
  list(m_6_no_fe, m_6_fe, m_12_no_fe, m_12_fe),
  list(title     = "Nitrate MR Violation Onset and Near-MCL Readings, 6- and 12-Month Lead/Lag Windows (National Sample, Downstream-2SLS-Sample States, CWS-Year)",
       label     = "tab:mr_concentration_lag_national_downstream_states_yearly",
       dict      = dict,
       headers   = list("Window" = c("6-month", "6-month", "12-month", "12-month")),
       notes     = note_main,
       fitstat   = ~n,
       style.tex = style.tex("aer", adjustbox = TRUE),
       tex       = TRUE,
       postprocess.tex = move_notes_below_adjustbox,
       file      = out_tex,
       replace   = TRUE)))

cat(sprintf("\nTable saved to: %s\n", out_tex))
if (file.exists(out_tex) && file.info(out_tex)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty -- check etable() call.")
}
cat("=== DONE ===\n")
