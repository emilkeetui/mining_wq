# ============================================================
# Script: sanitary_visit_syr2_enforcement_zscore_combined.r
# Purpose: CWS-month panel (strictly-downstream 2SLS sample, restricted to
#          the SYR2 window 1998-2005) testing whether SYR2 testing activity
#          across five chemicals (arsenic, nitrate, selenium, barium,
#          chromium) predicts an enforcement visit. Collapses the
#          per-chemical design of sanitary_visit_syr2_enforcement_zscore_iterative.r
#          into two binary indicators (any of the 5 chemicals tested in the
#          6-month lead/lag window, OR'd across chemicals) and two z-score
#          summaries (max and mean of the within-CWS-x-chemical z-scored
#          tested value, taken only over chemicals actually tested that
#          CWS-month). Dependent variable: 1 if an enforcement visit
#          (FENF/INVG/EMRG) occurred in that CWS-month (cols 1-3) or 1 if a
#          sanitary visit (SNSV/SNSP/SSVF) occurred in that CWS-month (cols 4-6).
#          Col 1: any-test-occurred leads/lags only, no FE (enforcement visit)
#          Col 2: + max/mean z-score controls, no FE (enforcement visit)
#          Col 3: + max/mean z-score controls, CWS + calendar-month FE (enforcement visit)
#          Col 4: any-test-occurred leads/lags only, no FE (sanitary visit)
#          Col 5: + max/mean z-score controls, no FE (sanitary visit)
#          Col 6: + max/mean z-score controls, CWS + calendar-month FE (sanitary visit)
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/reg/sanitary_visit_syr2_enforcement_zscore_combined.tex
# Author: EK  Date: 2026-07-13
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# SYR2 chemicals used for the test-timing / z-score covariates.
TARGET_CHEMS <- c("arsenic", "nitrate", "selenium", "barium", "chromium")

# ── 0. Sample: strictly-downstream CWSs ───────────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"),
    col_select = c("PWSID", "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0
sample_pwsids   <- unique(panel$PWSID[downstream_mask])
cat("Downstream CWSs in sample:", length(sample_pwsids), "\n")

month_idx_of <- function(d) {
  yr <- as.integer(format(d, "%Y"))
  mo <- as.integer(format(d, "%m"))
  (yr - 1985L) * 12L + (mo - 1L) + 1L
}
n_months <- month_idx_of(as.Date("2005-12-01"))

# ── 1. SYR2 measurements: per-chemical test occurrence + z-scores ────────────
syr2 <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"),
  col_select = c("PWSID", "sample_date", "CHEMID_name", "VALUE")))
syr2 <- syr2[PWSID %in% sample_pwsids & !is.na(sample_date) &
             CHEMID_name %in% TARGET_CHEMS & !is.na(VALUE)]
syr2[, sample_dt := as.Date(sample_date)]
syr2 <- syr2[!is.na(sample_dt)]
syr2[, month_idx := month_idx_of(sample_dt)]

has_syr2_pwsids <- unique(syr2$PWSID)
cat("Downstream CWSs with >=1 SYR2 measurement (5-chem restriction):", length(has_syr2_pwsids), "\n")

# Within-CWS x chemical z-score of the tested value (mirrors monitoring_retesting_hazard.r
# and sanitary_visit_syr2_enforcement_zscore_iterative.r)
syr2[, `:=`(v_mean = mean(VALUE), v_sd = sd(VALUE)), by = .(PWSID, CHEMID_name)]
syr2[, value_z := (VALUE - v_mean) / v_sd]
cat("PWSID x chemical combos with singleton SD (value_z = NA):",
    uniqueN(syr2[is.na(value_z), .(PWSID, CHEMID_name)]), "of",
    uniqueN(syr2[, .(PWSID, CHEMID_name)]), "combos\n")

# One row per CWS-month x chemical actually tested that month (long form --
# untested chemicals simply have no row, so max/mean below are not diluted
# toward 0 the way a 0-filled wide column would be).
syr2_pm_chem <- syr2[, .(value_z = value_z[.N]), by = .(PWSID, CHEMID_name, month_idx)]
test_dates_chem <- unique(syr2[, .(PWSID, CHEMID_name, month_idx)])

rm(syr2); gc()

# ── 2. Per-chemical 6-month lead/lag "test occurred" windows, then collapse ──
build_test_windows <- function(chem) {
  grp <- test_dates_chem[CHEMID_name == chem]
  cat(sprintf("  Chemical %-10s: %d test-months, %d CWSs\n",
              chem, nrow(grp), uniqueN(grp$PWSID)))
  tests_dd <- unique(grp[, .(PWSID, month_idx)])

  before_long <- tests_dd[, .(month_idx = seq(month_idx - 6L, month_idx - 1L)),
                             by = .(PWSID, test_month = month_idx)]
  after_long  <- tests_dd[, .(month_idx = seq(month_idx + 1L, month_idx + 6L)),
                             by = .(PWSID, test_month = month_idx)]

  b_pm <- unique(before_long[month_idx >= 1L & month_idx <= n_months, .(PWSID, month_idx)])
  a_pm <- unique(after_long[month_idx  >= 1L & month_idx <= n_months, .(PWSID, month_idx)])

  b_pm[[paste0(chem, "_before6")]] <- 1L
  a_pm[[paste0(chem, "_after6")]]  <- 1L

  m <- merge(b_pm, a_pm, by = c("PWSID", "month_idx"), all = TRUE)
  cat(sprintf("    before6=1: %d  after6=1: %d\n",
              sum(m[[paste0(chem, "_before6")]], na.rm = TRUE),
              sum(m[[paste0(chem, "_after6")]],  na.rm = TRUE)))
  m
}

cat("Building per-chemical test-occurrence lead/lag windows:\n")
test_win_list <- lapply(TARGET_CHEMS, build_test_windows)
test_win_pm <- Reduce(function(a, b) merge(a, b, by = c("PWSID", "month_idx"), all = TRUE),
                       test_win_list)

win_cols_before <- paste0(TARGET_CHEMS, "_before6")
win_cols_after  <- paste0(TARGET_CHEMS, "_after6")
for (cl in c(win_cols_before, win_cols_after)) {
  test_win_pm[is.na(get(cl)), (cl) := 0L]
}

# Collapse: any of the 5 target chemicals tested in the lead/lag window (OR).
test_win_pm[, any_syr2_before6 := as.integer(rowSums(.SD) > 0), .SDcols = win_cols_before]
test_win_pm[, any_syr2_after6  := as.integer(rowSums(.SD) > 0), .SDcols = win_cols_after]
any_win_pm <- test_win_pm[, .(PWSID, month_idx, any_syr2_before6, any_syr2_after6)]

cat(sprintf("Collapsed any-chemical windows -- any_syr2_before6=1: %d  any_syr2_after6=1: %d\n",
            sum(any_win_pm$any_syr2_before6), sum(any_win_pm$any_syr2_after6)))
cat(sprintf("Sanity check (union == OR of per-chemical columns): before6 %s, after6 %s\n",
            identical(sum(any_win_pm$any_syr2_before6),
                      sum(as.integer(rowSums(test_win_pm[, ..win_cols_before]) > 0))),
            identical(sum(any_win_pm$any_syr2_after6),
                      sum(as.integer(rowSums(test_win_pm[, ..win_cols_after]) > 0)))))

# ── 3. Collapsed z-score: max / mean of value_z across chemicals actually ────
#      tested that CWS-month (long-form groupby -- no 0-dilution).
zscore_combined <- syr2_pm_chem[, .(max_value_z  = max(value_z),
                                     mean_value_z_across_chems = mean(value_z)),
                                 by = .(PWSID, month_idx)]
cat("CWS-months with >=1 SYR2 test (z-score support):", nrow(zscore_combined), "\n")

# ── 4. Enforcement visit outcome (FENF/INVG/EMRG) ─────────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= 1985 & yr <= 2005]
sv[, month_idx := month_idx_of(visit_dt)]

enfv <- sv[VISIT_REASON_CODE %in% c("FENF", "INVG", "EMRG")]
cat("Enforcement visits (FENF/INVG/EMRG):", nrow(enfv), "in", uniqueN(enfv$PWSID), "CWSs\n")
enfv_pm <- unique(enfv[, .(PWSID, month_idx)])
enfv_pm[, enforcement_visit := 1L]

san <- sv[VISIT_REASON_CODE %in% c("SNSV", "SNSP", "SSVF")]
cat("Sanitary visits (SNSV/SNSP/SSVF):", nrow(san), "in", uniqueN(san$PWSID), "CWSs\n")
san_pm <- unique(san[, .(PWSID, month_idx)])
san_pm[, sanitary_visit := 1L]

rm(sv, enfv, san); gc()

# ── 5. Build SYR2-window CWS-month skeleton and merge ─────────────────────────
syr2_lo <- month_idx_of(as.Date("1998-01-01"))
syr2_hi <- month_idx_of(as.Date("2005-12-01"))

skel <- CJ(PWSID = has_syr2_pwsids, month_idx = seq(syr2_lo, syr2_hi))
skel <- merge(skel, any_win_pm,       by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, zscore_combined,  by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, enfv_pm,          by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, san_pm,           by = c("PWSID", "month_idx"), all.x = TRUE)

setorder(skel, PWSID, month_idx)

fill0_cols <- c("enforcement_visit", "sanitary_visit",
                "any_syr2_before6", "any_syr2_after6",
                "max_value_z", "mean_value_z_across_chems")
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]

# Calendar-month-of-year FE (Jan-Dec), not the running month_idx -- controls
# for testing/enforcement/sanitary-visit seasonality rather than absolute
# calendar time.
skel[, calendar_month := ((month_idx - 1L) %% 12L) + 1L]

cat("\nSYR2-window CWS-month panel:", nrow(skel), "rows (", length(has_syr2_pwsids),
    "CWSs x", syr2_hi - syr2_lo + 1L, "months)\n")
cat("enforcement_visit mean:", round(mean(skel$enforcement_visit), 4), "\n")
cat("sanitary_visit mean:   ", round(mean(skel$sanitary_visit), 4), "\n")

# ── 6. Regressions ─────────────────────────────────────────────────────────────
rhs_windows <- "any_syr2_before6 + any_syr2_after6"
rhs_zscores <- "max_value_z + mean_value_z_across_chems"

run_spec_no_fe <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs))
  feols(fml, data = dt, cluster = ~PWSID)
}
run_spec <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs, " | PWSID + calendar_month"))
  feols(fml, data = dt, cluster = ~PWSID)
}

m1 <- run_spec_no_fe("enforcement_visit", rhs_windows, skel)
m2 <- run_spec_no_fe("enforcement_visit", paste(rhs_windows, rhs_zscores, sep = " + "), skel)
m3 <- run_spec(      "enforcement_visit", paste(rhs_windows, rhs_zscores, sep = " + "), skel)

m4 <- run_spec_no_fe("sanitary_visit", rhs_windows, skel)
m5 <- run_spec_no_fe("sanitary_visit", paste(rhs_windows, rhs_zscores, sep = " + "), skel)
m6 <- run_spec(      "sanitary_visit", paste(rhs_windows, rhs_zscores, sep = " + "), skel)

cat("\n--- Enforcement visit, any-test windows only, no FE ---\n");           print(summary(m1))
cat("\n--- Enforcement visit, any-test windows + z-scores, no FE ---\n");     print(summary(m2))
cat("\n--- Enforcement visit, any-test windows + z-scores, CWS+month FE ---\n"); print(summary(m3))
cat("\n--- Sanitary visit, any-test windows only, no FE ---\n");              print(summary(m4))
cat("\n--- Sanitary visit, any-test windows + z-scores, no FE ---\n");        print(summary(m5))
cat("\n--- Sanitary visit, any-test windows + z-scores, CWS+month FE ---\n"); print(summary(m6))

# ── 7. LaTeX table ─────────────────────────────────────────────────────────────
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
  enforcement_visit = "Visit occurred in month t",
  sanitary_visit     = "Visit occurred in month t",
  any_syr2_before6   = "Any SYR2 test lead (1, 6) months",
  any_syr2_after6    = "Any SYR2 test lag (-6, -1) months",
  max_value_z        = "Max tested value (z-score)",
  mean_value_z_across_chems = "Mean tested value (z-score)",
  PWSID          = "CWS",
  calendar_month = "Calendar month (Jan-Dec)"
)

out_tex <- file.path(ROOT, "output/reg/sanitary_visit_syr2_enforcement_zscore_combined.tex")
note_main <- paste0(
  "Sample: downstream CWSs with >=1 SYR2 measurement of arsenic, nitrate, selenium, ",
  "barium, or chromium (", length(has_syr2_pwsids), "), CWS-months 1998-01 to 2005-12. ",
  "Outcome in columns (1)-(3) = 1 if an enforcement visit (FENF/INVG/EMRG) occurred at ",
  "that CWS in that calendar month; outcome in columns (4)-(6) = 1 if a sanitary visit ",
  "(SNSV/SNSP/SSVF) occurred at that CWS in that calendar month. Any SYR2 test lead/lag ",
  "collapse the five chemical-specific windows (arsenic, nitrate, selenium, barium, ",
  "chromium) via OR: before6 = 1 if the CWS-month falls in the 6 calendar months ",
  "preceding a SYR2 test of ANY of the five chemicals; after6 = 1 if it falls in the 6 ",
  "months following one; both are 0 outside any such window. Max/mean tested value ",
  "(z-score) = the max/mean, across chemicals actually tested that CWS-month, of ",
  "(tested value - CWS x chemical mean) / (CWS x chemical SD); both are 0 in CWS-months ",
  "with no SYR2 test of any of the five chemicals. Columns (3) and (6) include CWS fixed ",
  "effects and calendar-month-of-year fixed effects (Jan-Dec, not absolute calendar ",
  "time), which absorb seasonality in testing, enforcement, and sanitary-visit activity ",
  "rather than the specific year-month. Columns (1), (2), (4), (5) have no fixed ",
  "effects. N=", nrow(skel), " in all columns. SEs clustered at the CWS (PWSID) level ",
  "in all columns."
)

do.call(etable, c(
  list(m1, m2, m3, m4, m5, m6),
  list(title     = "SYR2 Testing Timing, Contaminant Levels, and Enforcement/Sanitary Visits (Collapsed)",
       label     = "tab:sanitary_visit_syr2_enforcement_zscore_combined",
       dict      = dict,
       headers   = list("Outcome" = c("Enforcement visit", "Enforcement visit", "Enforcement visit",
                                       "Sanitary visit", "Sanitary visit", "Sanitary visit")),
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
