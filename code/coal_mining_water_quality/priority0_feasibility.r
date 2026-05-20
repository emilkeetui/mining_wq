# ============================================================
# Script: priority0_feasibility.r
# Purpose: Priority 0 feasibility checks for structural model
#          Sample: downstream CWSs (2sls_dwnstrm_minevio_allcat.tex)
#          = minehuc_downstream_of_mine==1 & minehuc_mine==0, 1985-2005
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: console report (no files written)
# Author: EK  Date: 2026-05-07
# ============================================================

library(arrow)
library(fixest)
library(dplyr)
library(data.table)

# ---- Load main analysis sample (matches 2sls_dwnstrm_minevio_allcat.tex) ----
df <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
df <- df[df$PWSID != "WV3303401", ]

# Sample: downstream-only (not colocated), 1985-2005
sample_dwnstrm <- df |>
  filter(
    minehuc_downstream_of_mine == 1,
    minehuc_mine == 0,
    year >= 1985, year <= 2005,
    !is.na(sulfur_unified),
    !is.na(post95)
  )

pwsids_dwnstrm <- unique(sample_dwnstrm$PWSID)

cat("==========================================================\n")
cat("PRIORITY 0 FEASIBILITY CHECKS\n")
cat("Sample: downstream CWSs (2sls_dwnstrm_minevio_allcat.tex), 1985-2005\n")
cat("==========================================================\n")
cat(sprintf("N obs (PWSID×year): %d\n", nrow(sample_dwnstrm)))
cat(sprintf("N unique PWSIDs:    %d\n", length(pwsids_dwnstrm)))
cat("\n")


# ==========================================================
# CHECK 1: Enforcement chain data density
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 1: Enforcement chain data density\n")
cat("----------------------------------------------------------\n")

enf_path <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv"

enf_raw <- fread(enf_path, select = c(
  "PWSID", "VIOLATION_ID", "COMPL_PER_BEGIN_DATE",
  "ENF_ACTION_CATEGORY", "ENFORCEMENT_ACTION_TYPE_CODE",
  "ENF_ORIGINATOR_CODE", "VIOLATION_STATUS",
  "VIOLATION_CATEGORY_CODE", "CALCULATED_RTC_DATE",
  "IS_MAJOR_VIOL_IND"
), colClasses = "character")

# Filter to downstream sample and 1985-2005
enf_raw[, year := as.integer(substr(COMPL_PER_BEGIN_DATE, 7, 10))]
enf <- enf_raw[PWSID %in% pwsids_dwnstrm & year >= 1985 & year <= 2005]

cat(sprintf("Enforcement records in downstream sample (1985-2005): %d\n", nrow(enf)))
cat(sprintf("Unique PWSIDs with any enforcement record: %d / %d\n",
    length(unique(enf$PWSID)), length(pwsids_dwnstrm)))

# Enforcement chain states: violation → informal → formal → RTC
# Each enforcement record has a category
cat("\nEnforcement action category distribution:\n")
print(enf[, .N, by = ENF_ACTION_CATEGORY][order(-N)])

cat("\nViolation category distribution:\n")
print(enf[, .N, by = VIOLATION_CATEGORY_CODE][order(-N)])

# Count state transitions per PWSID: need at least informal + formal to estimate Markov
# A "chain" = PWSID with ≥1 informal AND ≥1 formal enforcement record
chain_cats <- enf[, .(
  has_informal = any(ENF_ACTION_CATEGORY == "Informal", na.rm = TRUE),
  has_formal   = any(ENF_ACTION_CATEGORY == "Formal",   na.rm = TRUE),
  has_resolving = any(ENF_ACTION_CATEGORY == "Resolving", na.rm = TRUE),
  has_rtc      = any(!is.na(CALCULATED_RTC_DATE) & CALCULATED_RTC_DATE != ""),
  n_records    = .N
), by = PWSID]

cat(sprintf("\nPWSIDs with informal enforcement:     %d\n", sum(chain_cats$has_informal)))
cat(sprintf("PWSIDs with formal enforcement:       %d\n", sum(chain_cats$has_formal)))
cat(sprintf("PWSIDs with resolving enforcement:    %d\n", sum(chain_cats$has_resolving)))
cat(sprintf("PWSIDs with RTC date:                 %d\n", sum(chain_cats$has_rtc)))

# Complete chains: informal + formal + RTC
complete_chains <- chain_cats[has_informal == TRUE & has_formal == TRUE & has_rtc == TRUE]
cat(sprintf("\nPWSIDs with COMPLETE chains (informal+formal+RTC): %d\n", nrow(complete_chains)))

# Count transition pairs: for Markov, need sequences within a PWSID
# Approximate: PWSIDs with ≥2 distinct enforcement categories over time
two_state_pwsids <- chain_cats[has_informal == TRUE & (has_formal == TRUE | has_resolving == TRUE)]
cat(sprintf("PWSIDs with ≥2 enforcement state transitions: %d\n", nrow(two_state_pwsids)))
cat(sprintf("Markov MLE feasibility threshold: 500 chains\n"))
cat(sprintf("Assessment: %s\n",
    ifelse(nrow(two_state_pwsids) >= 500,
           "FEASIBLE — sufficient transition pairs",
           "MARGINAL/INFEASIBLE — consider pooling states or simpler model")))

# RTC duration distribution
enf_rtc <- enf[!is.na(CALCULATED_RTC_DATE) & CALCULATED_RTC_DATE != "" &
                 !is.na(COMPL_PER_BEGIN_DATE) & COMPL_PER_BEGIN_DATE != ""]
if (nrow(enf_rtc) > 0) {
  enf_rtc[, viol_date := as.Date(COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
  enf_rtc[, rtc_date  := as.Date(CALCULATED_RTC_DATE,  format = "%m/%d/%Y")]
  enf_rtc[, days_to_rtc := as.numeric(rtc_date - viol_date)]
  valid_rtc <- enf_rtc[days_to_rtc >= 0 & days_to_rtc <= 3650]
  cat(sprintf("\nDays-to-RTC (N=%d): median=%d, mean=%.0f, p25=%d, p75=%d\n",
      nrow(valid_rtc),
      as.integer(median(valid_rtc$days_to_rtc, na.rm = TRUE)),
      mean(valid_rtc$days_to_rtc, na.rm = TRUE),
      as.integer(quantile(valid_rtc$days_to_rtc, 0.25, na.rm = TRUE)),
      as.integer(quantile(valid_rtc$days_to_rtc, 0.75, na.rm = TRUE))))
}
cat("\n")


# ==========================================================
# CHECK 2: Sanitary survey frequency
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 2: Sanitary survey frequency data\n")
cat("----------------------------------------------------------\n")

visits_path <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv"

visits_raw <- fread(visits_path, select = c(
  "PWSID", "VISIT_DATE", "VISIT_REASON_CODE",
  "AGENCY_TYPE_CODE", "COMPLIANCE_EVAL_CODE"
), colClasses = "character")

visits_raw[, year := as.integer(substr(VISIT_DATE, 7, 10))]
visits <- visits_raw[PWSID %in% pwsids_dwnstrm & year >= 1985 & year <= 2005]

cat(sprintf("Total site visit records in sample (1985-2005): %d\n", nrow(visits)))
cat(sprintf("Unique PWSIDs with any visit:                   %d / %d\n",
    length(unique(visits$PWSID)), length(pwsids_dwnstrm)))

cat("\nVisit reason code distribution:\n")
print(visits[, .N, by = VISIT_REASON_CODE][order(-N)])

# Sanitary surveys specifically
snsv <- visits[VISIT_REASON_CODE == "SNSV"]
cat(sprintf("\nSanitary surveys (SNSV): %d records\n", nrow(snsv)))
cat(sprintf("PWSIDs with ≥1 sanitary survey: %d / %d\n",
    length(unique(snsv$PWSID)), length(pwsids_dwnstrm)))

if (nrow(snsv) > 0) {
  snsv_panel <- snsv[, .(n_surveys = .N), by = .(PWSID, year)]
  cat(sprintf("PWSID×year observations with ≥1 survey: %d\n", nrow(snsv_panel)))
  cat(sprintf("Mean surveys per PWSID-year (conditional): %.2f\n",
      mean(snsv_panel$n_surveys)))

  # Coverage across years
  cat("\nSanitary survey coverage by year:\n")
  yr_coverage <- snsv[, .(n_snsv = .N, n_pwsids = uniqueN(PWSID)), by = year][order(year)]
  print(yr_coverage)

  # Within-PWSID variation
  snsv_pwsid <- snsv[, .(n_years_surveyed = uniqueN(year), n_total = .N), by = PWSID]
  cat(sprintf("\nPWSIDs with surveys in ≥3 years: %d\n",
      sum(snsv_pwsid$n_years_surveyed >= 3)))
  cat(sprintf("PWSIDs with surveys in ≥5 years: %d\n",
      sum(snsv_pwsid$n_years_surveyed >= 5)))
}

cat(sprintf("\nConclusion: sanitary survey data %s as a state variable\n",
    ifelse(length(unique(snsv$PWSID)) >= 200,
           "USABLE — sufficient PWSID coverage",
           "SPARSE — may need to impute or drop from state space")))
cat("\n")


# ==========================================================
# CHECK 3: MCL vs MR violation type granularity
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 3: MCL vs MR violation type granularity\n")
cat("----------------------------------------------------------\n")

mining_outcomes <- c("nitrates", "arsenic", "inorganic_chemicals", "radionuclides")
mcl_vars <- paste0(mining_outcomes, "_MCL_share_days")
mr_vars  <- paste0(mining_outcomes, "_MR_share_days")

# Non-zero observations
cat("Non-zero observations by violation type (mining-related outcomes):\n")
cat(sprintf("%-45s  %8s  %8s\n", "Variable", "N nonzero", "% nonzero"))
cat(sprintf("%-45s  %8s  %8s\n", "--------", "--------", "--------"))
for (v in c(mcl_vars, mr_vars)) {
  x <- sample_dwnstrm[[v]]
  n_nz <- sum(!is.na(x) & x > 0)
  pct  <- 100 * n_nz / sum(!is.na(x))
  cat(sprintf("%-45s  %8d  %7.1f%%\n", v, n_nz, pct))
}

# CWS with BOTH MCL and MR observations (within-PWSID variation needed for CCP)
cat("\nWithin-PWSID variation: PWSIDs with both MCL>0 and MR>0 (any year):\n")
for (contam in mining_outcomes) {
  mcl_v <- paste0(contam, "_MCL_share_days")
  mr_v  <- paste0(contam, "_MR_share_days")
  pws_both <- sample_dwnstrm |>
    group_by(PWSID) |>
    summarise(
      has_mcl = any(.data[[mcl_v]] > 0, na.rm = TRUE),
      has_mr  = any(.data[[mr_v]]  > 0, na.rm = TRUE)
    ) |>
    filter(has_mcl & has_mr)
  cat(sprintf("  %-25s: %d PWSIDs with both MCL>0 and MR>0\n", contam, nrow(pws_both)))
}

# CWSs with only MCL or only MR (also informative)
cat("\nPWSIDs with any MCL>0 (any mining outcome):\n")
any_mcl <- sample_dwnstrm |>
  group_by(PWSID) |>
  summarise(has_mcl = any(
    nitrates_MCL_share_days > 0 | arsenic_MCL_share_days > 0 |
    inorganic_chemicals_MCL_share_days > 0 | radionuclides_MCL_share_days > 0,
    na.rm = TRUE)) |>
  filter(has_mcl)
cat(sprintf("  %d / %d PWSIDs\n", nrow(any_mcl), length(pwsids_dwnstrm)))

any_mr <- sample_dwnstrm |>
  group_by(PWSID) |>
  summarise(has_mr = any(
    nitrates_MR_share_days > 0 | arsenic_MR_share_days > 0 |
    inorganic_chemicals_MR_share_days > 0 | radionuclides_MR_share_days > 0,
    na.rm = TRUE)) |>
  filter(has_mr)
cat(sprintf("PWSIDs with any MR>0 (any mining outcome): %d / %d PWSIDs\n",
    nrow(any_mr), length(pwsids_dwnstrm)))
cat("\n")


# ==========================================================
# CHECK 4: First-stage strength by violation type
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 4: First-stage and reduced-form by violation type\n")
cat("----------------------------------------------------------\n")

# 2SLS sample: downstream only (matches 2sls_dwnstrm_minevio_allcat.tex)
fs_sample <- sample_dwnstrm |>
  filter(!is.na(sulfur_unified), !is.na(post95), !is.na(num_coal_mines_upstream),
         !is.na(num_facilities))

# Add state variable
fs_sample$state <- fs_sample$STATE_CODE

cat(sprintf("Regression sample N (obs): %d, N (PWSIDs): %d\n",
    nrow(fs_sample), length(unique(fs_sample$PWSID))))
cat("\n")

# First stage: num_coal_mines_upstream ~ post95:sulfur_unified + FE
fs_main <- feols(num_coal_mines_upstream ~ post95:sulfur_unified + num_facilities |
                   PWSID + year + state,
                 data = fs_sample, cluster = ~PWSID)
cat("First stage (main): num_coal_mines_upstream ~ post95:sulfur_unified\n")
cat(sprintf("  Coeff on instrument: %.4f (SE: %.4f, t: %.2f)\n",
    coef(fs_main)["post95:sulfur_unified"],
    se(fs_main)["post95:sulfur_unified"],
    coef(fs_main)["post95:sulfur_unified"] / se(fs_main)["post95:sulfur_unified"]))
t_fs <- coef(fs_main)["post95:sulfur_unified"] / se(fs_main)["post95:sulfur_unified"]
cat(sprintf("  F-stat (instrument, t^2): %.1f\n", t_fs^2))
cat("\n")

# Reduced forms: MCL_share_days and MR_share_days on instrument (by contaminant)
cat("Reduced form: violation share (days) ~ post95:sulfur_unified + FE\n")
cat(sprintf("%-50s  %8s  %6s  %8s  %8s\n",
    "Outcome", "Coeff", "SE", "t-stat", "N"))
cat(sprintf("%-50s  %8s  %6s  %8s  %8s\n",
    "-------", "-----", "--", "------", "--"))

for (v in c(mcl_vars, mr_vars)) {
  if (all(is.na(fs_sample[[v]])) || sum(!is.na(fs_sample[[v]]) & fs_sample[[v]] > 0) < 10) {
    cat(sprintf("%-50s  %-40s\n", v, "SKIPPED (too few nonzero obs)"))
    next
  }
  tryCatch({
    rf <- feols(as.formula(paste(v, "~ post95:sulfur_unified + num_facilities | PWSID + year + state")),
                data = fs_sample, cluster = ~PWSID)
    b  <- coef(rf)["post95:sulfur_unified"]
    s  <- se(rf)["post95:sulfur_unified"]
    n  <- nobs(rf)
    cat(sprintf("%-50s  %8.5f  %6.5f  %8.2f  %8d\n", v, b, s, b/s, n))
  }, error = function(e) {
    cat(sprintf("%-50s  ERROR: %s\n", v, conditionMessage(e)))
  })
}

cat("\n")

# Also run total violation shares for comparison (allcat = what the main table uses)
cat("Reduced form: TOTAL (MCL+MR) mining violations (share_days) ~ instrument\n")
for (v in paste0(mining_outcomes, "_share_days")) {
  tryCatch({
    rf <- feols(as.formula(paste(v, "~ post95:sulfur_unified + num_facilities | PWSID + year + state")),
                data = fs_sample, cluster = ~PWSID)
    b  <- coef(rf)["post95:sulfur_unified"]
    s  <- se(rf)["post95:sulfur_unified"]
    n  <- nobs(rf)
    cat(sprintf("%-50s  %8.5f  %6.5f  %8.2f  %8d\n", v, b, s, b/s, n))
  }, error = function(e) {
    cat(sprintf("%-50s  ERROR: %s\n", v, conditionMessage(e)))
  })
}

cat("\n==========================================================\n")
cat("SUMMARY ASSESSMENT\n")
cat("==========================================================\n")
cat("Check 1 (Enforcement chains): see counts above\n")
cat("Check 2 (Sanitary surveys):   see counts above\n")
cat("Check 3 (MCL/MR granularity): see within-PWSID counts above\n")
cat("Check 4 (First-stage by type): see reduced-form t-stats above\n")
cat("==========================================================\n")
