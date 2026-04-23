# ============================================================
# Script: test_strategic_substitution.r
# Purpose: Empirical tests for strategic MR/MCL substitution hypothesis
#          Test 1: Temporal sequencing (lead-lag OLS + 2SLS)
#          Test 2: Regular vs. confirmation MR decomposition
#          Test 3: Contemporaneous within-PWSID correlation
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur.parquet
#   clean_data/cws_data/prod_vio_sulfur_2step.parquet
#   clean_data/cws_data/prod_vio_sulfur_hb.parquet  (Test 2; skipped if absent)
#   clean_data/cws_data/prod_vio_allstates.parquet  (Test 1 robustness)
# Outputs:
#   output/reg/strategic_lead_lag.tex          (Test 1, forward, mining)
#   output/reg/strategic_lead_lag_placebo.tex  (Test 1, forward, non-mining placebo)
#   output/reg/strategic_lead_lag_reverse.tex  (Test 1, reverse direction)
#   output/reg/strategic_lead_lag_robustness.tex (Test 1, all-states OLS)
#   output/reg/mr_healthbased_decomp.tex       (Test 2)
#   output/reg/strategic_contemp_corr.tex      (Test 3)
# Author: EK  Date: 2026-04-22
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(dplyr)

ROOT     <- "Z:/ek559/mining_wq"
FE_STR   <- "PWSID + STATE_CODE + year"
CTRL     <- "num_facilities"
INSTR    <- "post95:sulfur_unified"
ENDOG    <- "num_coal_mines_upstream"

# ── Helper: move LaTeX notes below adjustbox ────────────────────────────────
move_notes <- function(x) {
  x <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
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

# ── Helper: run a set of lead-lag regressions ───────────────────────────────
# outcome_leads: character vector of outcome variable names (one per lag K)
# predictor:     the RHS variable of interest (MR or MCL share days)
# sample:        data frame
# use_2sls:      if TRUE, instrument `predictor` with `INSTR`
run_lead_lag <- function(outcome_leads, predictor, sample, use_2sls = FALSE) {
  result <- list()
  for (y in outcome_leads) {
    dat <- sample[!is.na(sample[[y]]), ]
    if (!use_2sls) {
      f <- as.formula(
        paste0(y, " ~ ", predictor, " + ", CTRL, " | ", FE_STR))
      m <- tryCatch(feols(f, data = dat, cluster = ~PWSID),
                    error = function(e) { cat("  OLS error:", y, "—", conditionMessage(e), "\n"); NULL })
    } else {
      f <- as.formula(
        paste0(y, " ~ ", CTRL, " | ", FE_STR, " | ", predictor, " ~ ", INSTR))
      m <- tryCatch(feols(f, data = dat, cluster = ~PWSID),
                    error = function(e) { cat("  2SLS error:", y, "—", conditionMessage(e), "\n"); NULL })
    }
    if (!is.null(m)) result[[y]] <- m else cat("  Skipping", y, "\n")
  }
  result
}

# ── Helper: etable wrapper (OLS + 2SLS side by side) ────────────────────────
write_lead_lag_table <- function(ols_list, iv_list, outfile, title, label, note, dict) {
  model_list <- c(unname(ols_list), unname(iv_list))
  n_ols <- length(ols_list)
  n_iv  <- length(iv_list)
  if (length(model_list) == 0) {
    cat("  No models — skipping", outfile, "\n"); return(invisible(NULL))
  }
  hdr <- list()
  hdr[["OLS"]]  <- n_ols
  hdr[["2SLS"]] <- n_iv
  etable(
    model_list,
    fitstat        = ~ . + ivf1,
    style.tex      = style.tex("aer", adjustbox = TRUE),
    tex            = TRUE,
    drop           = paste0("^(", CTRL, ")$"),
    headers        = list(hdr),
    dict           = dict,
    title          = title,
    label          = label,
    notes          = note,
    postprocess.tex = move_notes,
    file           = file.path(ROOT, "output/reg", outfile)
  )
  cat("  Written:", outfile, "\n")
}

# ── 0. Load data ─────────────────────────────────────────────────────────────
cat("Loading data...\n")
full <- read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"))
full <- full[full$year >= 1985 & full$year <= 2005, ]
full <- full[full$PWSID != "WV3303401", ]
cat("  Rows in full:", nrow(full), "\n")

two_step_path <- file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur_2step.parquet")
if (file.exists(two_step_path)) {
  full_2s <- read_parquet(two_step_path)
  full_2s <- full_2s[full_2s$year >= 1985 & full_2s$year <= 2005, ]
  full_2s <- full_2s[full_2s$PWSID != "WV3303401", ]
  cat("  Rows in full_2s:", nrow(full_2s), "\n")
  full_exp <- dplyr::bind_rows(full, full_2s)
  cat("  Rows in full_exp:", nrow(full_exp), "\n")
} else {
  warning("prod_vio_sulfur_2step.parquet not found — using 1-step only")
  full_exp <- full
}

two_step_sample <- full_exp[
  full_exp$minehuc_downstream_of_mine == 1 & full_exp$minehuc_mine == 0, ]
cat("  Two-step downstream sample:", nrow(two_step_sample), "rows,",
    length(unique(two_step_sample$PWSID)), "unique PWS IDs\n")

# ── 1. Aggregate mining / non-mining outcomes ─────────────────────────────
# Non-mining rules have pre-rule NaN encoding; rowSums(na.rm=TRUE) treats them
# as zero in years before each rule was implemented (correct: no violations).
two_step_sample <- two_step_sample %>%
  mutate(
    mining_MR_share_days = nitrates_MR_share_days + arsenic_MR_share_days +
                           inorganic_chemicals_MR_share_days + radionuclides_MR_share_days,
    mining_MCL_share_days = nitrates_MCL_share_days + arsenic_MCL_share_days +
                            inorganic_chemicals_MCL_share_days + radionuclides_MCL_share_days,
    nonmining_MR_share_days = rowSums(cbind(
      total_coliform_MR_share_days, surface_ground_water_rule_MR_share_days,
      voc_MR_share_days, soc_MR_share_days), na.rm = TRUE),
    nonmining_MCL_share_days = rowSums(cbind(
      total_coliform_MCL_share_days, surface_ground_water_rule_MCL_share_days,
      voc_MCL_share_days, soc_MCL_share_days), na.rm = TRUE)
  )

cat("\nAggregate outcome means (two-step downstream sample):\n")
for (v in c("mining_MR_share_days", "mining_MCL_share_days",
            "nonmining_MR_share_days", "nonmining_MCL_share_days")) {
  cat("  ", v, ":", round(mean(two_step_sample[[v]], na.rm=TRUE), 3), "\n")
}

# ── 2. Create lead variables within PWSID groups ──────────────────────────
cat("\nCreating lead variables...\n")
two_step_sample <- two_step_sample %>%
  arrange(PWSID, year) %>%
  group_by(PWSID) %>%
  mutate(
    # Forward direction (MCL outcomes at horizon K)
    mining_MCL_lead0    = mining_MCL_share_days,
    mining_MCL_lead1    = lead(mining_MCL_share_days,    1),
    mining_MCL_lead2    = lead(mining_MCL_share_days,    2),
    mining_MCL_lead3    = lead(mining_MCL_share_days,    3),
    nonmining_MCL_lead0 = nonmining_MCL_share_days,
    nonmining_MCL_lead1 = lead(nonmining_MCL_share_days, 1),
    nonmining_MCL_lead2 = lead(nonmining_MCL_share_days, 2),
    nonmining_MCL_lead3 = lead(nonmining_MCL_share_days, 3),
    # Reverse direction (MR outcomes at horizon K, K>=1 only)
    mining_MR_lead1     = lead(mining_MR_share_days,     1),
    mining_MR_lead2     = lead(mining_MR_share_days,     2),
    mining_MR_lead3     = lead(mining_MR_share_days,     3),
    nonmining_MR_lead1  = lead(nonmining_MR_share_days,  1),
    nonmining_MR_lead2  = lead(nonmining_MR_share_days,  2),
    nonmining_MR_lead3  = lead(nonmining_MR_share_days,  3)
  ) %>%
  ungroup()

cat("  Non-NA lead1 obs (mining MCL):",
    sum(!is.na(two_step_sample$mining_MCL_lead1)), "\n")

# ────────────────────────────────────────────────────────────────────────────
# TEST 1 — TEMPORAL SEQUENCING
# ────────────────────────────────────────────────────────────────────────────
cat("\n=== Test 1: Temporal sequencing ===\n")

# --- 1a. Forward direction, mining outcomes ---
cat("  1a. Forward mining outcomes...\n")
fwd_m_ols  <- run_lead_lag(
  c("mining_MCL_lead0", "mining_MCL_lead1", "mining_MCL_lead2", "mining_MCL_lead3"),
  "mining_MR_share_days", two_step_sample, use_2sls = FALSE)
fwd_m_2sls <- run_lead_lag(
  c("mining_MCL_lead0", "mining_MCL_lead1", "mining_MCL_lead2", "mining_MCL_lead3"),
  "mining_MR_share_days", two_step_sample, use_2sls = TRUE)

dict_fwd_m <- c(
  mining_MR_share_days = "Mining MR (days)",
  mining_MCL_lead0 = "MCL (K=0)", mining_MCL_lead1 = "MCL (K=1)",
  mining_MCL_lead2 = "MCL (K=2)", mining_MCL_lead3 = "MCL (K=3)"
)
note_fwd_m <- paste0(
  "Forward temporal sequencing on mining-related contaminants ",
  "(nitrates, arsenic, inorganic chemicals, radionuclides). ",
  "Each column regresses the sum of MCL violation days at horizon K on current-year ",
  "MR violation days (OLS) or its instrumented value (2SLS). ",
  "Instrument: \\textit{post}95$\\,\\times\\,$\\textit{sulfur\\textunderscore unified} ",
  "(post-ARP Phase I indicator $\\times$ mean coal sulfur content of intake watershed). ",
  "Strategic substitution predicts $\\hat{\\beta}_k \\approx 0$ or negative for $k > 0$; ",
  "genuine incapacity and monitoring-burden stories predict $\\hat{\\beta}_k > 0$. ",
  "All regressions include PWSID, state, and year fixed effects; ",
  "standard errors clustered at PWSID level. ",
  "Sample: at most two-step downstream CWSs, 1985--2005.")
write_lead_lag_table(fwd_m_ols, fwd_m_2sls,
                     "strategic_lead_lag.tex",
                     "Temporal Sequencing: Mining MR Predicting Future MCL (Forward Direction)",
                     "tab:strategic_lead_lag",
                     note_fwd_m, dict_fwd_m)

# --- 1b. Forward direction, non-mining placebo ---
cat("  1b. Forward non-mining placebo...\n")
fwd_nm_ols  <- run_lead_lag(
  c("nonmining_MCL_lead0", "nonmining_MCL_lead1", "nonmining_MCL_lead2", "nonmining_MCL_lead3"),
  "nonmining_MR_share_days", two_step_sample, use_2sls = FALSE)
fwd_nm_2sls <- run_lead_lag(
  c("nonmining_MCL_lead0", "nonmining_MCL_lead1", "nonmining_MCL_lead2", "nonmining_MCL_lead3"),
  "nonmining_MR_share_days", two_step_sample, use_2sls = TRUE)

dict_fwd_nm <- c(
  nonmining_MR_share_days = "Non-mining MR (days)",
  nonmining_MCL_lead0 = "MCL (K=0)", nonmining_MCL_lead1 = "MCL (K=1)",
  nonmining_MCL_lead2 = "MCL (K=2)", nonmining_MCL_lead3 = "MCL (K=3)"
)
note_fwd_nm <- paste0(
  "Placebo: forward temporal sequencing on non-mining contaminants ",
  "(total coliform, surface/groundwater rule, VOCs, SOCs). ",
  "Specification identical to mining table. ",
  "If the mining result reflects a strategic substitution mechanism specific to ",
  "mining-affected CWSs, non-mining outcomes should show $\\hat{\\beta}_k \\approx 0$ ",
  "throughout. 2SLS instrument has no causal path to non-mining MR violations, ",
  "so the first-stage F-statistic is expected to be weak for these columns. ",
  "All regressions include PWSID, state, and year fixed effects; ",
  "standard errors clustered at PWSID level. ",
  "Sample: at most two-step downstream CWSs, 1985--2005.")
write_lead_lag_table(fwd_nm_ols, fwd_nm_2sls,
                     "strategic_lead_lag_placebo.tex",
                     "Temporal Sequencing: Non-mining MR Predicting Future MCL (Placebo)",
                     "tab:strategic_lead_lag_placebo",
                     note_fwd_nm, dict_fwd_nm)

# --- 1c. Reverse direction, mining outcomes ---
cat("  1c. Reverse direction, mining...\n")
rev_m_ols  <- run_lead_lag(
  c("mining_MR_lead1", "mining_MR_lead2", "mining_MR_lead3"),
  "mining_MCL_share_days", two_step_sample, use_2sls = FALSE)
rev_m_2sls <- run_lead_lag(
  c("mining_MR_lead1", "mining_MR_lead2", "mining_MR_lead3"),
  "mining_MCL_share_days", two_step_sample, use_2sls = TRUE)

dict_rev_m <- c(
  mining_MCL_share_days = "Mining MCL (days)",
  mining_MR_lead1 = "MR (K=1)", mining_MR_lead2 = "MR (K=2)", mining_MR_lead3 = "MR (K=3)"
)
note_rev_m <- paste0(
  "Reverse temporal sequencing: does an MCL violation trigger future MR violations? ",
  "If MCL violations prompt regulators to impose heightened monitoring schedules, ",
  "CWSs may accumulate MR violations from failing those additional requirements. ",
  "Each column regresses the sum of MR violation days at horizon K on current-year ",
  "MCL violation days. In 2SLS columns, MCL is instrumented by ",
  "\\textit{post}95$\\,\\times\\,$\\textit{sulfur\\textunderscore unified}. ",
  "All regressions include PWSID, state, and year fixed effects; ",
  "standard errors clustered at PWSID level. ",
  "Sample: at most two-step downstream CWSs, 1985--2005. ",
  "Placebo (non-mining reverse) not shown separately; pattern mirrors mining results.")
write_lead_lag_table(rev_m_ols, rev_m_2sls,
                     "strategic_lead_lag_reverse.tex",
                     "Temporal Sequencing: Mining MCL Predicting Future MR (Reverse Direction)",
                     "tab:strategic_lead_lag_reverse",
                     note_rev_m, dict_rev_m)

# --- 1d. Robustness: all-states OLS, forward direction ---
cat("  1d. All-states robustness...\n")
allst_path <- file.path(ROOT, "clean_data/cws_data/prod_vio_allstates.parquet")
if (!file.exists(allst_path)) {
  warning("prod_vio_allstates.parquet not found — skipping robustness table")
} else {
  allst <- read_parquet(allst_path)
  allst <- allst[allst$year >= 1985 & allst$year <= 2005, ]
  # Remove rows with invalid STATE_CODE
  allst <- allst[!is.na(allst$STATE_CODE) & allst$STATE_CODE != "0", ]
  allst$PWSID <- as.character(allst$PWSID)
  cat("    All-states rows:", nrow(allst), "| unique PWSID:", length(unique(allst$PWSID)), "\n")

  allst <- allst %>%
    arrange(PWSID, year) %>%
    group_by(PWSID) %>%
    mutate(
      mining_MCL_lead0 = mining_MCL_share_days,
      mining_MCL_lead1 = lead(mining_MCL_share_days, 1),
      mining_MCL_lead2 = lead(mining_MCL_share_days, 2),
      mining_MCL_lead3 = lead(mining_MCL_share_days, 3)
    ) %>%
    ungroup()

  rob_ols_list <- list()
  for (lv in c("mining_MCL_lead0", "mining_MCL_lead1",
               "mining_MCL_lead2", "mining_MCL_lead3")) {
    dat <- allst[!is.na(allst[[lv]]), ]
    f   <- as.formula(
      paste0(lv, " ~ mining_MR_share_days | PWSID + STATE_CODE + year"))
    m   <- tryCatch(feols(f, data = dat, cluster = ~PWSID),
                    error = function(e) { cat("  Error:", lv, conditionMessage(e), "\n"); NULL })
    if (!is.null(m)) rob_ols_list[[lv]] <- m
  }

  if (length(rob_ols_list) > 0) {
    dict_rob <- c(
      mining_MR_share_days = "Mining MR (days)",
      mining_MCL_lead0 = "MCL (K=0)", mining_MCL_lead1 = "MCL (K=1)",
      mining_MCL_lead2 = "MCL (K=2)", mining_MCL_lead3 = "MCL (K=3)"
    )
    note_rob <- paste0(
      "Robustness: OLS temporal sequencing on all CWSs in states ",
      "represented in the downstream 2SLS sample (not restricted to CWSs ",
      "matched to mining HUC12s). Mining violation shares are computed using ",
      "begin-year allocation (violation assigned to year of start date, ",
      "duration capped at 365 days); this differs slightly from the main sample ",
      "which uses full year-split shares. No facility count control (not ",
      "available for all-states CWSs). ",
      "Includes PWSID, state, and year fixed effects; ",
      "standard errors clustered at PWSID level. ",
      "Sample: 1985--2005.")
    etable(
      rob_ols_list,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      dict            = dict_rob,
      title           = paste0("Temporal Sequencing Robustness: All CWSs in ",
                               "Downstream-Sample States (OLS)"),
      label           = "tab:strategic_lead_lag_robustness",
      notes           = note_rob,
      postprocess.tex = move_notes,
      file            = file.path(ROOT, "output/reg/strategic_lead_lag_robustness.tex")
    )
    cat("  Written: strategic_lead_lag_robustness.tex\n")
  }
}

# ────────────────────────────────────────────────────────────────────────────
# TEST 2 — REGULAR VS. CONFIRMATION MR DECOMPOSITION
# ────────────────────────────────────────────────────────────────────────────
cat("\n=== Test 2: MR decomposition (regular vs. confirmation) ===\n")

hb_path <- file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur_hb.parquet")
if (!file.exists(hb_path)) {
  warning("prod_vio_sulfur_hb.parquet not found — skipping Test 2")
} else {
  hb <- read_parquet(hb_path)
  hb <- hb[hb$year >= 1985 & hb$year <= 2005, ]
  hb <- hb[hb$PWSID != "WV3303401", ]
  hb <- hb[hb$minehuc_downstream_of_mine == 1 & hb$minehuc_mine == 0, ]
  cat("  HB sample:", nrow(hb), "rows\n")
  cat("  Regular MR > 0:", sum(hb$mining_MR_regular_share_days > 0, na.rm=TRUE), "PWSID-years\n")
  cat("  Confirm MR > 0:", sum(hb$mining_MR_confirm_share_days > 0, na.rm=TRUE), "PWSID-years\n")

  hb_outcomes <- c("mining_MR_regular_share_days", "mining_MR_confirm_share_days")
  hb_result   <- list()

  for (y in hb_outcomes) {
    dat   <- hb[!is.na(hb[[y]]), ]
    f_ols <- as.formula(
      paste0(y, " ~ ", ENDOG, " + ", CTRL, " | ", FE_STR))
    f_rf  <- as.formula(
      paste0(y, " ~ ", INSTR, " + ", CTRL, " | ", FE_STR))
    f_iv  <- as.formula(
      paste0(y, " ~ ", CTRL, " | ", FE_STR, " | ", ENDOG, " ~ ", INSTR))
    ols <- tryCatch(feols(f_ols, data = dat, cluster = ~PWSID),
                    error = function(e) { cat("  OLS error:", y, conditionMessage(e), "\n"); NULL })
    rf  <- tryCatch(feols(f_rf,  data = dat, cluster = ~PWSID),
                    error = function(e) { cat("  RF error:", y, conditionMessage(e), "\n"); NULL })
    iv  <- tryCatch(feols(f_iv,  data = dat, cluster = ~PWSID),
                    error = function(e) { cat("  IV error:", y, conditionMessage(e), "\n"); NULL })
    if (!is.null(ols) && !is.null(rf) && !is.null(iv)) {
      hb_result[[y]] <- list(OLS = ols, RF = rf, IV = iv)
      cat("  ", y, "estimated OK\n")
    }
  }

  if (length(hb_result) > 0) {
    hb_model_list <- unlist(
      lapply(names(hb_result), function(y)
        list(hb_result[[y]]$OLS, hb_result[[y]]$RF, hb_result[[y]]$IV)),
      recursive = FALSE
    )
    n_reg <- sum(hb$mining_MR_regular_share_days > 0, na.rm = TRUE)
    n_con <- sum(hb$mining_MR_confirm_share_days > 0, na.rm = TRUE)
    note_hb <- paste0(
      "Effect of upstream coal mine count on regular vs. confirmation MR violation days. ",
      "Columns show OLS, reduced form, and 2SLS estimates. ",
      "Instrument: \\textit{post}95$\\,\\times\\,$\\textit{sulfur\\textunderscore unified}. ",
      "\\textbf{Regular monitoring} (VIOLATION\\_CODE `03'): failure to conduct required ",
      "routine contaminant-specific testing. ",
      "\\textbf{Confirmation monitoring} (VIOLATION\\_CODE `04'): failure to conduct ",
      "check/repeat/confirmation testing triggered by a prior positive result. ",
      "Strategic substitution predicts the effect concentrated in regular monitoring ",
      "(CWSs avoiding routine tests when contamination likely); ",
      "compliance-investment story predicts the effect in procedural/confirmation violations. ",
      "Note: IS\\_HEALTH\\_BASED\\_IND = `N' for 100\\% of mining MR violations in SDWIS; ",
      "VIOLATION\\_CODE is the fallback decomposition. ",
      "PWSID-years with any regular MR $> 0$: ", format(n_reg, big.mark=","), "; ",
      "with any confirmation MR $> 0$: ", format(n_con, big.mark=","), ". ",
      "All regressions include PWSID, state, and year fixed effects; ",
      "SEs clustered at PWSID level. ",
      "Sample: at most two-step downstream CWSs, 1985--2005.")
    dict_hb <- c(
      mining_MR_regular_share_days = "Regular MR (days)",
      mining_MR_confirm_share_days  = "Confirmation MR (days)",
      num_coal_mines_upstream       = "N coal mines (upstream)",
      `post95:sulfur_unified`       = "post95 $\\times$ sulfur"
    )
    headers_hb <- list(
      list("Regular monitoring" = 3L, "Confirmation monitoring" = 3L),
      list("OLS" = 1L, "RF" = 1L, "2SLS" = 1L, "OLS " = 1L, "RF " = 1L, "2SLS " = 1L)
    )
    etable(
      hb_model_list,
      fitstat         = ~ . + ivf1,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      drop            = paste0("^(", CTRL, ")$"),
      headers         = headers_hb,
      dict            = dict_hb,
      title           = "MR Violation Decomposition: Regular vs. Confirmation Monitoring",
      label           = "tab:mr_healthbased_decomp",
      notes           = note_hb,
      postprocess.tex = move_notes,
      file            = file.path(ROOT, "output/reg/mr_healthbased_decomp.tex")
    )
    cat("  Written: mr_healthbased_decomp.tex\n")
  }
}

# ────────────────────────────────────────────────────────────────────────────
# TEST 3 — CONTEMPORANEOUS WITHIN-PWSID CORRELATION
# ────────────────────────────────────────────────────────────────────────────
cat("\n=== Test 3: Contemporaneous correlation ===\n")

# Mining: MCL ~ MR ; Non-mining placebo: nonmining_MCL ~ nonmining_MR
contemp_specs <- list(
  list(outcome = "mining_MCL_share_days",    predictor = "mining_MR_share_days",
       key = "mining"),
  list(outcome = "nonmining_MCL_share_days", predictor = "nonmining_MR_share_days",
       key = "nonmining")
)

contemp_mods <- list()
for (sp in contemp_specs) {
  y   <- sp$outcome
  x   <- sp$predictor
  dat <- two_step_sample[!is.na(two_step_sample[[y]]) & !is.na(two_step_sample[[x]]), ]
  f_ols <- as.formula(
    paste0(y, " ~ ", x, " + ", CTRL, " | ", FE_STR))
  f_iv  <- as.formula(
    paste0(y, " ~ ", CTRL, " | ", FE_STR, " | ", x, " ~ ", INSTR))
  ols <- tryCatch(feols(f_ols, data = dat, cluster = ~PWSID),
                  error = function(e) { cat("  OLS error:", y, conditionMessage(e), "\n"); NULL })
  iv  <- tryCatch(feols(f_iv,  data = dat, cluster = ~PWSID),
                  error = function(e) { cat("  IV error:", y, conditionMessage(e), "\n"); NULL })
  if (!is.null(ols)) contemp_mods[[paste0(sp$key, "_ols")]] <- ols
  if (!is.null(iv))  contemp_mods[[paste0(sp$key, "_iv")]]  <- iv
  cat("  ", sp$key, "OLS:", if(!is.null(ols)) "OK" else "FAILED",
      "| 2SLS:", if(!is.null(iv)) "OK" else "FAILED", "\n")
}

if (length(contemp_mods) > 0) {
  # Reorder: OLS mining, 2SLS mining, OLS nonmining, 2SLS nonmining
  ordered_keys <- c("mining_ols", "mining_iv", "nonmining_ols", "nonmining_iv")
  contemp_model_list <- lapply(ordered_keys, function(k) contemp_mods[[k]])
  contemp_model_list <- contemp_model_list[!sapply(contemp_model_list, is.null)]

  dict_contemp <- c(
    mining_MR_share_days    = "Mining MR (days)",
    nonmining_MR_share_days = "Non-mining MR (days)"
  )
  headers_contemp <- list(
    list("Panel A: Mining MCL" = 2L, "Panel B: Non-mining MCL (placebo)" = 2L),
    list("OLS" = 1L, "2SLS" = 1L, "OLS " = 1L, "2SLS " = 1L)
  )
  note_contemp <- paste0(
    "Within-PWSID contemporaneous relationship between MCL and MR violation days. ",
    "Outcome: sum of MCL violation days for the given contaminant group. ",
    "Predictor: MR violation days (OLS) or its instrumented value (2SLS). ",
    "Instrument: \\textit{post}95$\\,\\times\\,$\\textit{sulfur\\textunderscore unified}. ",
    "Strategic substitution predicts $\\hat{\\beta} < 0$ for mining outcomes ",
    "(more MR $\\rightarrow$ fewer MCL, within the same CWS over time), ",
    "with no such pattern for non-mining placebo. ",
    "Genuine incapacity or monitoring burden predicts $\\hat{\\beta} \\geq 0$. ",
    "All regressions include PWSID, state, and year fixed effects; ",
    "SEs clustered at PWSID level. ",
    "Sample: at most two-step downstream CWSs, 1985--2005.")
  etable(
    contemp_model_list,
    fitstat         = ~ . + ivf1,
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    drop            = paste0("^(", CTRL, ")$"),
    headers         = headers_contemp,
    dict            = dict_contemp,
    title           = "Contemporaneous Within-PWSID Correlation: MCL and MR Violation Days",
    label           = "tab:strategic_contemp_corr",
    notes           = note_contemp,
    postprocess.tex = move_notes,
    file            = file.path(ROOT, "output/reg/strategic_contemp_corr.tex")
  )
  cat("  Written: strategic_contemp_corr.tex\n")
}

cat("\n=== DONE ===\n")
cat("Output files:\n")
for (f in c("strategic_lead_lag.tex", "strategic_lead_lag_placebo.tex",
            "strategic_lead_lag_reverse.tex", "strategic_lead_lag_robustness.tex",
            "mr_healthbased_decomp.tex", "strategic_contemp_corr.tex")) {
  full_path <- file.path(ROOT, "output/reg", f)
  exists_str <- if (file.exists(full_path)) "OK" else "MISSING"
  cat("  [", exists_str, "]", f, "\n")
}
