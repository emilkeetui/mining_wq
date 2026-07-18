# ============================================================
# Script: mr_concentration_lag_national_downstream_states_yearly_reconciled.r
# Purpose: Reconciled CWS-year version of
#          mr_concentration_lag_national_downstream_states.r (reading-level).
#          The original _yearly.r's outcome ("any nitrate MR violation onset
#          in that calendar year", sourced from a separate SDWA join) was
#          found to test a structurally different hypothesis than the
#          reading-level script's mr_same_fwd/mr_same_fwd6mon outcome ("MR
#          onset in the forward window of THIS SPECIFIC reading") -- see
#          .claude/logs/2026-07-16-mr_concentration_lag_downstream_states_
#          vs_yearly_comparison.md. This script reconciles the two by
#          making the CWS-year outcome reading-anchored: a CWS-year is
#          coded 1 only if a reading in its lag window itself had a
#          positive mr_same_fwd/mr_same_fwd6mon (an MR onset actually
#          followed THAT reading within its own forward window), directly
#          nesting the reading-level causal logic inside the CWS-year
#          rollup grain. mr_same_fwd/mr_same_fwd6mon are already
#          precomputed at reading level in the source parquet, so no fresh
#          join against SDWA_VIOLATIONS_ENFORCEMENT is needed (unlike the
#          original _yearly.r).
#            near_mcl_lead6/lead12   = 1 if any reading at 50-100% of the
#                                       MCL occurred in the 6/12 months
#                                       AFTER some month in that CWS-year
#            near_mcl_lag6/lag12     = 1 if any such reading occurred in
#                                       the 6/12 months BEFORE
#            mean_conc_z_lead6/lag6/... = mean of the PWSID-YEAR z-scored
#                                       concentration among readings in
#                                       that window (0 if no reading)
#            mr_reading_triggered_lag6/lag12 = 1 if any reading in the LAG
#                                       window (6/12mo) itself had
#                                       mr_same_fwd6mon/mr_same_fwd == 1,
#                                       i.e. an MR onset followed THAT
#                                       reading within its own forward
#                                       window. This is the new outcome
#                                       (replaces mr_violation).
#          Col 1: 6-month windows,  no FE
#          Col 2: 6-month windows,  CWS + year FE
#          Col 3: 12-month windows, no FE
#          Col 4: 12-month windows, CWS + year FE
# Inputs:  clean_data/mr_concentration_lag_national_nitrate.parquet
# Outputs: output/reg/mr_concentration_lag_national_downstream_states_yearly_reconciled.tex
# Author: EK  Date: 2026-07-17
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
  col_select = c("PWSID", "sample_date", "YEAR", "VALUE", "near_mcl",
                 "mr_same_fwd", "mr_same_fwd6mon")))

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
cat("mr_same_fwd==1 readings:", sum(syr2$mr_same_fwd == 1, na.rm = TRUE), "\n")
cat("mr_same_fwd6mon==1 readings:", sum(syr2$mr_same_fwd6mon == 1, na.rm = TRUE), "\n")

# ── 2. Build lead/lag window indicators + window-mean z-score + reading-
#       triggered MR outcome, per horizon, at CWS-month grain first
#       (day-level precision), then roll up to CWS-year (a year's
#       indicator = 1 if any month in that year has the window indicator
#       = 1; z-score = mean across that year's months). The reading-
#       triggered outcome is built from the LAG window only: only past
#       readings have forward windows that could have already resolved by
#       CWS-year t. h=6 uses mr_same_fwd6mon (1-182 day forward window);
#       h=12 uses mr_same_fwd (1-365 day forward window) -- matching the
#       horizon of mr_concentration_lag_national_downstream_states.r's
#       two columns. ─────────────────────────────────────────────────────
build_windows_yearly <- function(h) {
  mr_fwd_col <- if (h == 6L) "mr_same_fwd6mon" else "mr_same_fwd"

  # One row per PWSID x reading-month, collapsing multiple same-month
  # readings to: presence of a near-MCL reading, the mean z-score that
  # month, and whether ANY reading that month had a positive forward-
  # window MR outcome (reading-triggered).
  d <- syr2[, .(near_mcl     = as.integer(any(near_mcl == 1)),
                mean_conc_z  = mean(mean_conc_z, na.rm = TRUE),
                mr_triggered = as.integer(any(get(mr_fwd_col) == 1))),
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
  lag_pm  <- lag_long[,  .(near_mcl_lag       = as.integer(any(near_mcl == 1)),
                            mean_conc_z_lag     = mean(mean_conc_z, na.rm = TRUE),
                            mr_reading_triggered = as.integer(any(mr_triggered == 1))),
                        by = .(PWSID, month_idx)]

  win_pm <- merge(lead_pm, lag_pm, by = c("PWSID", "month_idx"), all = TRUE)
  win_pm[is.na(near_mcl_lead),         near_mcl_lead         := 0L]
  win_pm[is.na(near_mcl_lag),          near_mcl_lag          := 0L]
  win_pm[is.na(mean_conc_z_lead),      mean_conc_z_lead      := 0]
  win_pm[is.na(mean_conc_z_lag),       mean_conc_z_lag       := 0]
  win_pm[is.na(mr_reading_triggered),  mr_reading_triggered  := 0L]

  # Roll up CWS-month -> CWS-year.
  win_pm[, year := year_of_month_idx(month_idx)]
  win_py <- win_pm[, .(near_mcl_lead        = as.integer(any(near_mcl_lead == 1)),
                        near_mcl_lag         = as.integer(any(near_mcl_lag  == 1)),
                        mean_conc_z_lead     = mean(mean_conc_z_lead),
                        mean_conc_z_lag      = mean(mean_conc_z_lag),
                        mr_reading_triggered = as.integer(any(mr_reading_triggered == 1))),
                    by = .(PWSID, year)]

  setnames(win_py,
    c("near_mcl_lead", "near_mcl_lag", "mean_conc_z_lead", "mean_conc_z_lag", "mr_reading_triggered"),
    paste0(c("near_mcl_lead", "near_mcl_lag", "mean_conc_z_lead", "mean_conc_z_lag", "mr_reading_triggered_lag"), h))
  win_py
}

cat("Building 6-month lead/lag windows...\n")
win6  <- build_windows_yearly(6L)
cat("Building 12-month lead/lag windows...\n")
win12 <- build_windows_yearly(12L)

# ── 3. Build CWS-year skeleton and merge ──────────────────────────────────────
skel <- CJ(PWSID = sample_pwsids, year = seq(year_lo, year_hi))
skel <- merge(skel, win6,  by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, win12, by = c("PWSID", "year"), all.x = TRUE)
setorder(skel, PWSID, year)

win_cols   <- c("near_mcl_lead6", "near_mcl_lag6", "near_mcl_lead12", "near_mcl_lag12")
z_cols     <- c("mean_conc_z_lead6", "mean_conc_z_lag6", "mean_conc_z_lead12", "mean_conc_z_lag12")
y_cols     <- c("mr_reading_triggered_lag6", "mr_reading_triggered_lag12")
fill0_cols <- c(win_cols, z_cols, y_cols)
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]

cat("\nCWS-year panel:", nrow(skel), "rows (", length(sample_pwsids),
    "CWSs x", year_hi - year_lo + 1L, "years)\n")
cat("mr_reading_triggered_lag6 mean:", round(mean(skel$mr_reading_triggered_lag6), 6), "\n")
cat("mr_reading_triggered_lag12 mean:", round(mean(skel$mr_reading_triggered_lag12), 6), "\n")

# ── 4. Regressions ─────────────────────────────────────────────────────────────
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

m_6_no_fe  <- run_spec_no_fe("mr_reading_triggered_lag6",  rhs_6mon,  skel)
m_6_fe     <- run_spec(      "mr_reading_triggered_lag6",  rhs_6mon,  skel)
m_12_no_fe <- run_spec_no_fe("mr_reading_triggered_lag12", rhs_12mon, skel)
m_12_fe    <- run_spec(      "mr_reading_triggered_lag12", rhs_12mon, skel)

cat("\n--- Reading-triggered MR (6-month lag window), no FE ---\n");         print(summary(m_6_no_fe))
cat("\n--- Reading-triggered MR (6-month lag window), CWS+year FE ---\n");   print(summary(m_6_fe))
cat("\n--- Reading-triggered MR (12-month lag window), no FE ---\n");        print(summary(m_12_no_fe))
cat("\n--- Reading-triggered MR (12-month lag window), CWS+year FE ---\n");  print(summary(m_12_fe))

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
  mr_reading_triggered_lag6  = "MR onset in fwd. window of a lag(-6,-1)mo. reading",
  mr_reading_triggered_lag12 = "MR onset in fwd. window of a lag(-12,-1)mo. reading",
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

out_tex <- file.path(ROOT, "output/reg/mr_concentration_lag_national_downstream_states_yearly_reconciled.tex")
note_main <- paste0(
  "Reconciled CWS-year version of mr\\_concentration\\_lag\\_national\\_downstream\\_states.tex ",
  "(reading-level); see .claude/logs/2026-07-16-mr\\_concentration\\_lag\\_downstream\\_states\\_",
  "vs\\_yearly\\_comparison.md and .claude/logs/2026-07-17-mr-concentration-lag-yearly-",
  "reconciliation.md for reconciliation rationale. Sample: national SYR2 nitrate sample ",
  "restricted to states with at least one CWS in the main downstream 2SLS sample ",
  "(minehuc\\_downstream\\_of\\_mine==1 \\& minehuc\\_mine==0, 1985--2005), nitrate only (",
  length(sample_pwsids), " CWSs), CWS-years 1997 to 2005. Outcome (reading-anchored, nests ",
  "the reading-level script's causal logic): 1 if any SYR2 nitrate reading in the 6- or ",
  "12-month LAG window of some month in that CWS-year itself had a nitrate MR ",
  "(monitoring/reporting) violation onset in ITS OWN forward window (mr\\_same\\_fwd6mon for ",
  "the 6-month column, mr\\_same\\_fwd for the 12-month column, matching the reading-level ",
  "script's outcome variables exactly). near\\_mcl lead/lag = 1 if any SYR2 nitrate reading ",
  "at 50--100\\% of the MCL (the 40 CFR 141.23(d)(2) quarterly-monitoring trigger, n=",
  n_near_mcl, " readings) occurred in the 6 or 12 calendar months following (lead) or ",
  "preceding (lag) any month in that CWS-year; both are 0 outside any such window (built at ",
  "CWS-month grain from day-level reading dates, then rolled up to the CWS-year: the year ",
  "indicator is 1 if any of its 12 months has the monthly window indicator equal to 1). Mean ",
  "concen. (z-score) lead/lag = mean, across that CWS-year's months, of the PWSID-YEAR mean ",
  "concentration (z-scored across the sample) among readings in the same lead/lag window; 0 ",
  "in months with no reading in that window. Note: the near\\_mcl\\_lag regressor and the ",
  "reading-triggered outcome both condition on the same lag-window reading population by ",
  "construction (the outcome asks whether that reading's own forward MR onset materialized); ",
  "this mechanical overlap is expected and is what makes this table nest the reading-level ",
  "specification. Columns (2) and (4) include CWS and year fixed effects; columns (1) and ",
  "(3) have no fixed effects. N=", nrow(skel), " in all columns. SEs clustered at the CWS ",
  "(PWSID) level in all columns."
)

do.call(etable, c(
  list(m_6_no_fe, m_6_fe, m_12_no_fe, m_12_fe),
  list(title     = "Reading-Anchored Nitrate MR Violation Outcome and Near-MCL Readings, 6- and 12-Month Lead/Lag Windows (National Sample, Downstream-2SLS-Sample States, CWS-Year, Reconciled)",
       label     = "tab:mr_concentration_lag_national_downstream_states_yearly_reconciled",
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
