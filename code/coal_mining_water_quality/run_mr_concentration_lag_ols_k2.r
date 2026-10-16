# ============================================================
# Script: run_mr_concentration_lag_ols_k2.r
# Purpose: Reproduce the mr_concentration_lag_ols.r nitrate MR-violation
#          lag regression (near_mcl / mean_conc_z -> forward-window MR
#          violation), swapping that script's fixed production
#          downstream-of-mine PWSID set for the step-instrument grid's
#          k=2 main-arm PWSID set (n_mine_hucs_linked >= 1). Same
#          measurement-level SYR2 file, same violation-window matching
#          logic (ported inline, nitrate-only — mr_same_fwd/fwd6mon do
#          not need the rule333/anyioc machinery), same regression
#          formula. Terminal-only diagnostic: no .tex, no clean_data/ or
#          output/ writes, no changes to the production pipeline.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_6year_review_measurement_level_syr2.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: terminal printout, and (as of 2026-09-14, extending the original
#          terminal-only diagnostic per the k2 main.tex table plan)
#          output/reg/mr_concentration_lag_ols_k2.tex (+ _present.tex)
# Author: EK  Date: 2026-09-14
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
VIOL_PATH <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet"
NITRATE_CODE <- "1040"

# ── Step 1: k=2 main-arm PWSID universe (A2 intake-purity screened) ──────
si <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(si$PWSID))
step_purity <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_purity_flags.parquet"))
k2_pwsids <- si %>% filter(arm == "main", k == 2, n_mine_hucs_linked >= 1) %>%
  inner_join(filter(step_purity, arm == "main", k == 2, a2_pure == 1) %>% select(PWSID),
             by = "PWSID") %>%
  pull(PWSID) %>% unique()
cat(sprintf("k=2 main-arm PWSID universe: %d CWSs\n", length(k2_pwsids)))

# ── Step 2: SYR2 measurement-level nitrate readings, restricted to k=2 ──
meas <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"))
stopifnot(is.character(meas$PWSID))
meas <- meas %>% filter(PWSID %in% k2_pwsids, contaminant_code == NITRATE_CODE)
cat(sprintf("Nitrate SYR2 measurement rows in k=2 main arm: %d (%d distinct CWSs)\n",
            nrow(meas), n_distinct(meas$PWSID)))

# ── Step 3: MR violations, nitrate only, restricted to k=2 (same window ─
#    logic as build_mr_concentration_lag.py's mr_same_fwd/fwd6mon, ported
#    inline since only the same-contaminant match is needed here) ───────
cat("\nReading MR violations (column-projected, PWSID-filtered)...\n")
viol <- read_parquet(VIOL_PATH,
                      col_select = c("PWSID", "NON_COMPL_PER_BEGIN_DATE",
                                     "VIOLATION_CATEGORY_CODE", "CONTAMINANT_CODE"))
viol$PWSID <- as.character(viol$PWSID)
viol <- viol %>% filter(VIOLATION_CATEGORY_CODE == "MR", PWSID %in% k2_pwsids,
                         CONTAMINANT_CODE == NITRATE_CODE)
viol$viol_date <- as.Date(viol$NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")
viol <- viol[!is.na(viol$viol_date) & format(viol$viol_date, "%Y") >= "1990", ]
cat(sprintf("Nitrate MR violations in k=2 main arm: %d rows (%d distinct CWSs)\n",
            nrow(viol), n_distinct(viol$PWSID)))

dates_by_pwsid <- viol %>% group_by(PWSID) %>%
  summarise(dates = list(sort(viol_date)), .groups = "drop")
dates_lookup <- setNames(dates_by_pwsid$dates, dates_by_pwsid$PWSID)

window_count <- function(sorted_dates, lo, hi) {
  if (is.null(sorted_dates) || length(sorted_dates) == 0) return(0L)
  sum(sorted_dates >= lo & sorted_dates <= hi)
}

meas$sample_date <- as.Date(meas$sample_date)
meas$mr_same_fwd     <- 0L
meas$mr_same_fwd6mon <- 0L
for (i in seq_len(nrow(meas))) {
  pwsid <- meas$PWSID[i]
  d     <- dates_lookup[[pwsid]]
  s     <- meas$sample_date[i]
  meas$mr_same_fwd[i]     <- as.integer(window_count(d, s + 1,   s + 365) > 0)
  meas$mr_same_fwd6mon[i] <- as.integer(window_count(d, s + 1,   s + 182) > 0)
}
cat(sprintf("mr_same_fwd mean: %.4f | mr_same_fwd6mon mean: %.4f\n",
            mean(meas$mr_same_fwd), mean(meas$mr_same_fwd6mon)))

# ── Step 4: same spec as mr_concentration_lag_ols.r ──────────────────────
nit_df <- meas
nit_df$mean_concentration <- ave(nit_df$VALUE, nit_df$PWSID, nit_df$YEAR, FUN = mean)
nit_df$mean_conc_z <- scale(nit_df$mean_concentration)[, 1]

n_near_mcl <- sum(nit_df$near_mcl == 1, na.rm = TRUE)
cat(sprintf("Nitrate (k=2) subset N = %d | near_mcl==1 readings: %d\n", nrow(nit_df), n_near_mcl))

nit_df_lpm <- nit_df
nit_df_lpm$mr_same_fwd     <- as.numeric(nit_df$mr_same_fwd)     * 100
nit_df_lpm$mr_same_fwd6mon <- as.numeric(nit_df$mr_same_fwd6mon) * 100

fml_fwd     <- mr_same_fwd     ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_fwd6mon <- mr_same_fwd6mon ~ near_mcl + mean_conc_z | PWSID + YEAR

fwd     <- tryCatch(feols(fml_fwd,     data = nit_df_lpm, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                     error = function(e) { cat("ERROR (fwd):", conditionMessage(e), "\n"); NULL })
fwd6mon <- tryCatch(feols(fml_fwd6mon, data = nit_df_lpm, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                     error = function(e) { cat("ERROR (fwd6mon):", conditionMessage(e), "\n"); NULL })

cat("\n==================== k=2 main-arm nitrate MR lag regression ====================\n")
cat("(same spec as output/reg/mr_concentration_lag_ols.tex; national downstream-of-mine\n")
cat(" sample swapped for the step-grid's k=2 main-arm sample)\n\n")
if (!is.null(fwd))     { cat("--- Nitrate MR (1-yr fwd window) ---\n");  print(summary(fwd)) }
if (!is.null(fwd6mon)) { cat("\n--- Nitrate MR (6-mon fwd window) ---\n"); print(summary(fwd6mon)) }

cat("\nFor comparison, published (national downstream-of-mine, N=851):\n")
cat("  1-yr:  near_mcl 58.97** (24.60) | mean_conc_z 1.28 (1.43)\n")
cat("  6-mon: near_mcl 26.11** (10.53) | mean_conc_z 0.05 (0.87)\n")

# Shared table-formatting helpers (writes nothing on load)
source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

# ── Step 5: LaTeX table (extends the original terminal-only diagnostic per
# the k2 main.tex table plan), rendered with the shared k2 coefficient-table
# helper in k2_common.r ───────────────────────────────────────────────────
if (!is.null(fwd) && !is.null(fwd6mon)) {
  note_k2_fn <- function(extra) paste0(
    "\\textit{Notes:} SYR2 sample restricted to utilities with a coal mine within two ",
    "flow steps upstream of their intake and no coal mine colocated with their intake ",
    "(1998--2005), nitrate only. Outcome: nitrate MR (monitoring/reporting) violation ",
    "in the 365 days following the contaminant concentration sample date for the ",
    "1-yr column; violation in the 182 days following the contaminant concentration ",
    "sample date for the 6-mon column. Concen. $>$ 50\\% MCL = reading at ",
    "50--100\\% of the MCL (5 mg/L), which triggers quarterly rather than the ",
    "baseline annual nitrate testing. Mean concentration = ",
    "utility-year mean reading, z-scored within chemical. Coefficients and standard ",
    "errors are in percentage points. ", extra, " Standard errors clustered at the ",
    "utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )
  note_k2_present <- paste0(
    "\\textit{Notes:} All specifications include utility and year fixed effects. ",
    "Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )
  render_coef_table_k2(
    rows = list(
      list(label = "Concen. $>$ 50\\% MCL",     terms = list(get_term(fwd, "near_mcl"),     get_term(fwd6mon, "near_mcl"))),
      list(label = "Mean concen. (z-score)",    terms = list(get_term(fwd, "mean_conc_z"),  get_term(fwd6mon, "mean_conc_z")))
    ),
    col_headers = c("Nitrate MR (1-yr)", "Nitrate MR (6-mon)"), colnums = FALSE,
    fe_list     = list("Utility" = c(TRUE, TRUE), "Year" = c(TRUE, TRUE)),
    n_obs       = c(nobs(fwd), nobs(fwd6mon)),
    n_utils     = c(length(fixest::fixef(fwd)$PWSID), length(fixest::fixef(fwd6mon)$PWSID)),
    label       = "tab:mr_concentration_lag_ols_k2",
    title       = "Nitrate MR violations following a reading above 50\\% of the MCL",
    outfile     = "mr_concentration_lag_ols_k2",
    note_text_fn = note_k2_fn, notes_present = note_k2_present,
    label_w_cm  = 5, data_w_cm = 2.5
  )
  for (f in c("mr_concentration_lag_ols_k2.tex", "mr_concentration_lag_ols_k2_present.tex")) {
    p <- file.path(ROOT, "output/reg", f)
    cat(sprintf("Output verified: %s exists=%s size=%d\n", p, file.exists(p), file.size(p)))
  }
} else {
  cat("\n[ERROR] fwd or fwd6mon model failed -- skipping .tex render.\n")
}


cat("\nDone.\n")
