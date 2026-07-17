# ============================================================
# Script: syr2_test_mr_violation_bychem_leadonly_nolagmean_test.r
# Purpose: Test variant of syr2_test_mr_violation_bychem_leadonly_test.r --
#          same CWS-month panel (strictly-downstream 2SLS sample,
#          1997-2005), same chemical-matched pair specs (nitrate/331,
#          arsenic/332, IOC-barium+selenium/333), and same restriction
#          to CWSs with >=1 SYR2 measurement of the matched chemical(s),
#          but the regression RHS drops mean_value_z (lagged running
#          mean value, z-score) and keeps only:
#            - syr2_before6 (SYR2 test lead (1,6) months)
#            - value_z (lagged test value, z-score)
#          Col 1: nitrate,  no FE      Col 2: nitrate,  CWS + calendar-month FE
#          Col 3: arsenic,  no FE      Col 4: arsenic,  CWS + calendar-month FE
#          Col 5: IOC(333), no FE      Col 6: IOC(333), CWS + calendar-month FE
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: output/reg/syr2_test_mr_violation_bychem_leadonly_nolagmean_test.tex
# Author: EK  Date: 2026-07-16
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# Chemical-matched spec definitions: MR rule code <-> SYR2 chemical(s).
spec_defs <- list(
  nitrate = list(rule = 331L, chems = c("nitrate")),
  arsenic = list(rule = 332L, chems = c("arsenic")),
  ioc     = list(rule = 333L, chems = c("barium", "selenium"))
)

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
skel_lo  <- month_idx_of(as.Date("1997-01-01"))
skel_hi  <- month_idx_of(as.Date("2005-12-01"))

# ── 1. MR violation onsets, all IOC rules (331/332/333), loaded once ─────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE", "RULE_CODE")))
ve <- ve[PWSID %in% sample_pwsids]
ve[, rule_tmp := suppressWarnings(as.integer(RULE_CODE))]

onsets_all <- unique(ve[VIOLATION_CATEGORY_CODE == "MR" & rule_tmp %in% c(331L, 332L, 333L),
  .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE, rule_tmp)])
onsets_all[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets_all <- onsets_all[!is.na(onset_dt)]
onsets_all[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets_all <- onsets_all[onset_yr >= 1997 & onset_yr <= 2005]
onsets_all[, month_idx := month_idx_of(onset_dt)]

rm(ve); gc()

# ── 2. SYR2 measurements, all target chemicals, loaded once ──────────────────
all_chems <- unique(unlist(lapply(spec_defs, `[[`, "chems")))
syr2_all <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"),
  col_select = c("PWSID", "sample_date", "CHEMID_name", "VALUE")))
syr2_all <- syr2_all[PWSID %in% sample_pwsids & !is.na(sample_date) &
                      CHEMID_name %in% all_chems & !is.na(VALUE)]
syr2_all[, sample_dt := as.Date(sample_date)]
syr2_all <- syr2_all[!is.na(sample_dt)]
syr2_all[, yr := as.integer(format(sample_dt, "%Y"))]
syr2_all <- syr2_all[yr >= 1985 & yr <= 2005]
syr2_all[, month_idx := month_idx_of(sample_dt)]

# Within-CWS x chemical z-score of the tested value (running mean is computed
# for consistency with the source script but dropped from the RHS below).
syr2_all[, `:=`(v_mean = mean(VALUE), v_sd = sd(VALUE)), by = .(PWSID, CHEMID_name)]
syr2_all[, value_z := (VALUE - v_mean) / v_sd]
setorder(syr2_all, PWSID, CHEMID_name, sample_dt)

# Last test that CWS-month x chemical, used to build the LOCF lagged series below.
syr2_pm_chem <- syr2_all[, .(value_z = value_z[.N]), by = .(PWSID, CHEMID_name, month_idx)]

# ── 3. Build the before6/after6 window indicator for a set of test months ────
# after6 is still computed (kept in the panel) but is not included in the
# regression RHS below -- only syr2_before6 is used from this pair.
build_test_windows <- function(tests_dd) {
  before_long <- tests_dd[, .(month_idx = seq(month_idx - 6L, month_idx - 1L)),
                              by = .(PWSID, test_month = month_idx)]
  after_long  <- tests_dd[, .(month_idx = seq(month_idx + 1L, month_idx + 6L)),
                              by = .(PWSID, test_month = month_idx)]

  b_pm <- unique(before_long[month_idx >= 1L & month_idx <= n_months, .(PWSID, month_idx)])
  a_pm <- unique(after_long[month_idx  >= 1L & month_idx <= n_months, .(PWSID, month_idx)])

  b_pm[, syr2_before6 := 1L]
  a_pm[, syr2_after6  := 1L]

  merge(b_pm, a_pm, by = c("PWSID", "month_idx"), all = TRUE)
}

# For a set of chemicals, build the CWS-month lagged (LOCF) value_z series --
# the most recent test's z-score carried forward to every subsequent month.
# When >1 chemical (IOC spec), average across chemicals' lagged series for
# that CWS-month.
build_lagged_zscores <- function(chems) {
  d <- syr2_pm_chem[CHEMID_name %in% chems]
  pwsids <- unique(d$PWSID)
  skel_z <- CJ(PWSID = pwsids, month_idx = seq_len(n_months))
  setkey(skel_z, PWSID, month_idx)

  locf_one_chem <- function(chem) {
    dd <- d[CHEMID_name == chem, .(PWSID, month_idx, value_z)]
    setkey(dd, PWSID, month_idx)
    out <- dd[skel_z, roll = TRUE, on = .(PWSID, month_idx)]
    out[, CHEMID_name := chem]
    out
  }
  stacked <- rbindlist(lapply(chems, locf_one_chem))
  stacked[, .(value_z = mean(value_z, na.rm = TRUE)), by = .(PWSID, month_idx)]
}

# ── 4. Build one CWS-month skeleton + run both FE variants per chem-spec ─────
run_spec_no_fe <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs))
  feols(fml, data = dt, cluster = ~PWSID)
}
run_spec <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs, " | PWSID + calendar_month"))
  feols(fml, data = dt, cluster = ~PWSID)
}

build_and_run <- function(spec_name, rule, chems) {
  cat(sprintf("\n=== Spec: %s (rule %d, chems: %s) ===\n",
              spec_name, rule, paste(chems, collapse = ", ")))

  mr_pm <- unique(onsets_all[rule_tmp == rule, .(PWSID, month_idx)])
  mr_pm[, mr_violation := 1L]
  cat("  MR onset CWS-months:", nrow(mr_pm), "\n")

  syr2 <- syr2_all[CHEMID_name %in% chems]
  has_syr2_pwsids <- unique(syr2$PWSID)
  cat("  Downstream CWSs with >=1 SYR2 measurement of", paste(chems, collapse = "/"),
      ":", length(has_syr2_pwsids), "\n")

  tests_dd <- unique(syr2[, .(PWSID, month_idx)])
  test_pm  <- build_test_windows(tests_dd)
  cat(sprintf("  before6=1: %d  after6=1: %d\n",
              sum(test_pm$syr2_before6, na.rm = TRUE),
              sum(test_pm$syr2_after6,  na.rm = TRUE)))

  lagged_z <- build_lagged_zscores(chems)

  skel <- CJ(PWSID = has_syr2_pwsids, month_idx = seq(skel_lo, skel_hi))
  skel <- merge(skel, mr_pm,    by = c("PWSID", "month_idx"), all.x = TRUE)
  skel <- merge(skel, test_pm,  by = c("PWSID", "month_idx"), all.x = TRUE)
  skel <- merge(skel, lagged_z, by = c("PWSID", "month_idx"), all.x = TRUE)
  setorder(skel, PWSID, month_idx)

  fill0_cols <- c("mr_violation", "syr2_before6", "syr2_after6")
  for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]
  # Lagged z-score control stays NA before a CWS's first test of the relevant
  # chemical(s) -- feols() drops those rows for the models that include it.
  skel[, calendar_month := ((month_idx - 1L) %% 12L) + 1L]

  cat("  CWS-month panel:", nrow(skel), "rows (", length(has_syr2_pwsids),
      "CWSs x", skel_hi - skel_lo + 1L, "months)\n")
  cat("  mr_violation mean:", round(mean(skel$mr_violation), 4), "\n")
  cat("  CWS-months with a lagged z-score available:",
      sum(!is.na(skel$value_z)), "of", nrow(skel), "\n")

  # Lead-only, no-lag-mean RHS: syr2_before6 + value_z only.
  rhs_full <- "syr2_before6 + value_z"

  m_no_fe <- run_spec_no_fe("mr_violation", rhs_full, skel)
  m_fe    <- run_spec(      "mr_violation", rhs_full, skel)

  cat(sprintf("\n--- %s MR violation, SYR2 test lead only, no lagged mean, no FE ---\n", spec_name))
  print(summary(m_no_fe))
  cat(sprintf("\n--- %s MR violation, SYR2 test lead only, no lagged mean, CWS+month FE ---\n", spec_name))
  print(summary(m_fe))

  list(m_no_fe = m_no_fe, m_fe = m_fe, n = nobs(m_no_fe), n_pwsids = length(has_syr2_pwsids))
}

results <- lapply(names(spec_defs), function(nm)
  build_and_run(nm, spec_defs[[nm]]$rule, spec_defs[[nm]]$chems))
names(results) <- names(spec_defs)

# ── 5. LaTeX table ─────────────────────────────────────────────────────────────
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
  mr_violation   = "MR violation onset in month t",
  syr2_before6   = "SYR2 test lead (1, 6) months",
  value_z        = "Lagged test value (z-score)",
  PWSID          = "CWS",
  calendar_month = "Calendar month (Jan-Dec)"
)

out_tex <- file.path(ROOT, "output/reg/syr2_test_mr_violation_bychem_leadonly_nolagmean_test.tex")
note_main <- paste0(
  "TEST SPEC: lead-only, no-lagged-mean variant of syr2_test_mr_violation_bychem_iterative.r -- ",
  "the SYR2 test lag (-6,-1) months indicator and the lagged running mean value ",
  "(z-score) are both dropped from the RHS; only the lead window and the lagged ",
  "test value (z-score) are included. Sample: downstream CWSs, CWS-months 1997-01 ",
  "to 2005-12. Each pair of columns restricts to CWSs with >=1 SYR2 measurement of ",
  "the relevant chemical(s): nitrate (", results$nitrate$n_pwsids, " CWSs, N=",
  results$nitrate$n, "), arsenic (", results$arsenic$n_pwsids, " CWSs, N=",
  results$arsenic$n, "), barium/selenium (", results$ioc$n_pwsids, " CWSs, N=",
  results$ioc$n, "). Outcome = 1 if an MR violation onset under the matched IOC ",
  "rule occurs in that CWS-month: nitrate rule 331 (cols 1-2), arsenic rule 332 ",
  "(cols 3-4), inorganic chemicals rule 333 (cols 5-6). before6 = 1 if the ",
  "CWS-month falls in the 6 calendar months preceding any SYR2 (Six-Year Review 2) ",
  "test of the matched chemical(s) (nitrate for cols 1-2, arsenic for cols 3-4, ",
  "barium or selenium for cols 5-6); 0 otherwise. Lagged test value (z-score) = ",
  "(tested value - CWS x chemical mean) / (CWS x chemical SD) from the most ",
  "recent test of the matched chemical(s) at or before that CWS-month, carried ",
  "forward until the next test. For the IOC spec (cols 5-6), barium and ",
  "selenium's lagged z-scores are averaged. Value is undefined (and the ",
  "CWS-month dropped from estimation) before a CWS's first test of the matched ",
  "chemical(s). Columns (2), (4), (6) include CWS fixed effects and ",
  "calendar-month-of-year fixed effects (Jan-Dec, not absolute calendar time), ",
  "which absorb seasonality in violation reporting rather than the specific ",
  "year-month. Columns (1), (3), (5) have no fixed effects. SEs clustered at the ",
  "CWS (PWSID) level in all columns."
)

do.call(etable, c(
  list(results$nitrate$m_no_fe, results$nitrate$m_fe,
       results$arsenic$m_no_fe, results$arsenic$m_fe,
       results$ioc$m_no_fe,     results$ioc$m_fe),
  list(title     = "SYR2 Test Lead and MR Violation Onset, by Chemical (Test: Lead-Only, No Lagged Mean)",
       label     = "tab:syr2_test_mr_violation_bychem_leadonly_nolagmean_test",
       dict      = dict,
       headers   = list("Nitrate MR" = 2, "Arsenic MR" = 2, "IOC MR" = 2),
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
