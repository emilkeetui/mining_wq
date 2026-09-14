# ============================================================
# Script: render_step_instrument_grid.r
# Purpose: Re-render the terminal comparison tables from
#          run_step_instrument_grid.r's saved results, without
#          re-running any estimation. Reads only the two results
#          parquets; no raw_data/output writes.
# Inputs:
#   clean_data/cws_data/step_grid_results.parquet
#   clean_data/cws_data/step_grid_firststage.parquet
# Outputs:
#   (terminal printout only)
# Author: EK  Date: 2026-09-13
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(arrow)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"

res_df <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_grid_results.parquet"))
fs_df  <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_grid_firststage.parquet"))

cat(sprintf("Loaded %d coefficient rows and %d first-stage rows.\n", nrow(res_df), nrow(fs_df)))

OUTCOMES <- c(
  nitrates_MR_bin              = "Nitrates (MR)",
  arsenic_MR_bin               = "Arsenic (MR)",
  inorganic_chemicals_MR_bin   = "Inorganic chemicals (MR)",
  nitrates_MCL_bin             = "Nitrates (MCL)",
  arsenic_MCL_bin              = "Arsenic (MCL)",
  inorganic_chemicals_MCL_bin  = "Inorganic chemicals (MCL)",
  any_snsv                     = "Sanitary visit",
  any_enfvisit                 = "Enforcement visit",
  any_formal                   = "Formal enforcement",
  any_informal                 = "Informal enforcement"
)
K_VALS   <- 1:8
FE_LABEL <- c("PWSID+year", "PWSID+year+state x year")

fmt <- function(x, d = 2) ifelse(is.na(x), "NA", sprintf(paste0("%.", d, "f"), x))
stars <- function(p) ifelse(is.na(p), "", ifelse(p < 0.01, "***", ifelse(p < 0.05, "**", ifelse(p < 0.1, "*", ""))))

# ============================================================
# BLOCK 1 — not reproducible from saved results
# ============================================================
cat("\n\n==================== BLOCK 1: Sample & Instrument Composition ====================\n")
cat("SKIPPED — sample-composition fields (n_hucs_covered, cov_share, n_hucs_linked,\n")
cat("any_active_mine_in_window) are not stored in step_grid_results.parquet /\n")
cat("step_grid_firststage.parquet. Re-run run_step_instrument_grid.r to regenerate Block 1.\n")

# ============================================================
# BLOCK 2 — First stage
# ============================================================
cat("\n\n==================== BLOCK 2: First Stage (clustered F) ====================\n")
cat("F < 10 flagged WEAK. Coefficient (SE) on post95:sulfur_var.\n\n")
cat(sprintf("%-4s %-8s %-13s %-24s %6s %6s %12s %8s\n",
            "k", "arm", "column", "FE", "N_CWS", "N_obs", "coef(SE)", "F"))
for (i in seq_len(nrow(fs_df))) {
  r <- fs_df[i, ]
  coef_se <- sprintf("%s(%s)", fmt(r$fs_coef, 4), fmt(r$fs_se, 4))
  f_flag  <- if (!is.na(r$f_clustered) && r$f_clustered < 10) paste0(fmt(r$f_clustered), " WEAK") else fmt(r$f_clustered)
  cat(sprintf("%-4d %-8s %-13s %-24s %6d %6d %12s %8s\n",
              r$k, r$arm, r$column, r$fe, r$n_cws, r$n_obs, coef_se, f_flag))
}

# ============================================================
# BLOCKS 3-6 — One per outcome family (2SLS coef(SE), main vs placebo)
# ============================================================
families <- list(
  "BLOCK 3: MR Violations"    = c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin"),
  "BLOCK 4: MCL Violations"   = c("nitrates_MCL_bin", "arsenic_MCL_bin", "inorganic_chemicals_MCL_bin"),
  "BLOCK 5: Regulator Visits" = c("any_snsv", "any_enfvisit"),
  "BLOCK 6: Enforcement"      = c("any_formal", "any_informal")
)

for (fam_name in names(families)) {
  ocs <- families[[fam_name]]
  cat(sprintf("\n\n==================== %s (2SLS, percentage points) ====================\n", fam_name))
  for (oc in ocs) {
    cat(sprintf("\n-- %s --\n", OUTCOMES[[oc]]))
    cat(sprintf("%-4s %-13s %-24s %-20s %-20s\n", "k", "column", "FE", "main coef(SE)", "placebo coef(SE)"))
    for (kk in K_VALS) {
      for (column_name in c("A-full", "A-restricted", "B")) {
        for (fe_lab in FE_LABEL) {
          m <- res_df %>% filter(k == kk, arm == "main", column == column_name, fe == fe_lab,
                                  outcome == oc, model == "IV")
          p <- res_df %>% filter(k == kk, arm == "placebo", column == column_name, fe == fe_lab,
                                  outcome == oc, model == "IV")
          if (nrow(m) == 0 && nrow(p) == 0) next
          m_str <- if (nrow(m) == 1) sprintf("%s%s(%s)", fmt(m$coef), stars(m$pval), fmt(m$se)) else "--"
          p_str <- if (nrow(p) == 1) sprintf("%s%s(%s)", fmt(p$coef), stars(p$pval), fmt(p$se)) else "--"
          cat(sprintf("%-4d %-13s %-24s %-20s %-20s\n", kk, column_name, fe_lab, m_str, p_str))
        }
      }
    }
  }
}
cat("\nStars: *** p<0.01, ** p<0.05, * p<0.1. Units: percentage points (binary outcomes x100).\n")

# ============================================================
# BLOCK 7 — Decomposition read (A-full vs A-restricted vs B), headline MR
# ============================================================
cat("\n\n==================== BLOCK 7: Decomposition Read (headline MR outcomes, main arm) ====================\n")
cat("A-full vs A-restricted = sample-composition effect. A-restricted vs B = instrument-value effect.\n\n")
for (kk in K_VALS) {
  for (fe_lab in FE_LABEL) {
    cat(sprintf("\n-- k=%d, %s --\n", kk, fe_lab))
    cat(sprintf("%-30s %-14s %-14s %-14s\n", "outcome", "A-full", "A-restricted", "B"))
    for (oc in c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin")) {
      af <- res_df %>% filter(k == kk, arm == "main", column == "A-full",       fe == fe_lab, outcome == oc, model == "IV")
      ar <- res_df %>% filter(k == kk, arm == "main", column == "A-restricted", fe == fe_lab, outcome == oc, model == "IV")
      bb <- res_df %>% filter(k == kk, arm == "main", column == "B",            fe == fe_lab, outcome == oc, model == "IV")
      f1 <- if (nrow(af) == 1) sprintf("%s(%s)", fmt(af$coef), fmt(af$se)) else "--"
      f2 <- if (nrow(ar) == 1) sprintf("%s(%s)", fmt(ar$coef), fmt(ar$se)) else "--"
      f3 <- if (nrow(bb) == 1) sprintf("%s(%s)", fmt(bb$coef), fmt(bb$se)) else "--"
      cat(sprintf("%-30s %-14s %-14s %-14s\n", OUTCOMES[[oc]], f1, f2, f3))
    }
  }
}

# ============================================================
# BLOCK 8 — Summary read
# ============================================================
cat("\n\n==================== BLOCK 8: Summary Read ====================\n")
cat("Per k: does main hold up (any significant MR at p<0.1, column B), is placebo null, are both first stages strong (F>=10)?\n")
cat("A placebo null under a weak placebo first stage is flagged VACUOUS, not a pass.\n\n")
cat(sprintf("%-4s %-24s %-10s %-12s %-14s %-14s %-10s\n",
            "k", "FE", "main_sig", "placebo_sig", "main_F", "placebo_F", "verdict"))
for (kk in K_VALS) {
  for (fe_lab in FE_LABEL) {
    main_b <- res_df %>% filter(k == kk, arm == "main", column == "B", fe == fe_lab,
                                 outcome %in% c("nitrates_MR_bin","arsenic_MR_bin","inorganic_chemicals_MR_bin"),
                                 model == "IV")
    plac_b <- res_df %>% filter(k == kk, arm == "placebo", column == "B", fe == fe_lab,
                                 outcome %in% c("nitrates_MR_bin","arsenic_MR_bin","inorganic_chemicals_MR_bin"),
                                 model == "IV")
    main_sig <- if (nrow(main_b) > 0) any(main_b$pval < 0.1, na.rm = TRUE) else NA
    plac_sig <- if (nrow(plac_b) > 0) any(plac_b$pval < 0.1, na.rm = TRUE) else NA
    f_main <- fs_df %>% filter(k == kk, arm == "main",    column == "B", fe == fe_lab) %>% pull(f_clustered)
    f_plac <- fs_df %>% filter(k == kk, arm == "placebo", column == "B", fe == fe_lab) %>% pull(f_clustered)
    f_main <- if (length(f_main) == 1) f_main else NA_real_
    f_plac <- if (length(f_plac) == 1) f_plac else NA_real_
    verdict <- if (is.na(f_plac) || f_plac < 10) {
      "VACUOUS"
    } else if (isTRUE(main_sig) && !isTRUE(plac_sig)) {
      "CLEAN"
    } else if (isTRUE(main_sig) && isTRUE(plac_sig)) {
      "BOTH SIG"
    } else {
      "NULL BOTH"
    }
    cat(sprintf("%-4d %-24s %-10s %-12s %-14s %-14s %-10s\n",
                kk, fe_lab, ifelse(is.na(main_sig), "NA", main_sig), ifelse(is.na(plac_sig), "NA", plac_sig),
                fmt(f_main), fmt(f_plac), verdict))
  }
}

# ============================================================
# Reproduction checks (Step 5)
# ============================================================
cat("\n\n==================== Reproduction Checks (Step 5) ====================\n")
chk_af <- fs_df %>% filter(k == 1, arm == "main", column == "A-full", fe == "PWSID+year")
chk_b  <- fs_df %>% filter(k == 1, arm == "main", column == "B",      fe == "PWSID+year")
cat(sprintf("k=1 main A-full: %d CWSs, %d obs, F=%s  (anchor: 340 / 6232 / 27.52)\n",
            ifelse(nrow(chk_af)==1, chk_af$n_cws, NA), ifelse(nrow(chk_af)==1, chk_af$n_obs, NA),
            ifelse(nrow(chk_af)==1, fmt(chk_af$f_clustered), "NA")))
cat(sprintf("k=1 main B:      %d CWSs, F=%s  (anchor: 253 / F~=12.29)\n",
            ifelse(nrow(chk_b)==1, chk_b$n_cws, NA), ifelse(nrow(chk_b)==1, fmt(chk_b$f_clustered), "NA")))
chk_b_state <- fs_df %>% filter(k == 1, arm == "main", column == "B", fe == "PWSID+year+state x year")
cat(sprintf("k=1 main B (+state x year): F=%s  (anchor: F~=17.20)\n",
            ifelse(nrow(chk_b_state)==1, fmt(chk_b_state$f_clustered), "NA")))
cat("NOTE: 45 extra CWSs appear in this diagnostic's A-full k=1 sample relative to the\n")
cat("340-CWS anchor (385 vs 340) — traced to a legacy sdwismatch exclusion (drops PWSIDs\n")
cat("mixing an unclassified-HUC facility with a non-upstream-classified one) that this\n")
cat("simpler linkage does not replicate; see session log for detail. The 6,232 existing\n")
cat("rows/PWSIDs are all exactly reproduced within this broader sample.\n")

cat("\nDone.\n")
