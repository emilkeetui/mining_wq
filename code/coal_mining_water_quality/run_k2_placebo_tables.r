# ============================================================
# Script: run_k2_placebo_tables.r
# Purpose: Placebo-arm (purity-screened) k=2 A-full step-instrument-grid
#          geographical placebo tables for main.tex: MR/MCL binary-violation
#          2SLS panels, visit-type, and enforcement-type panels, on utilities
#          with a coal mine within two flow steps downstream of their intake
#          and no coal mine upstream. Sources k2_common.r. Captions/notes
#          describe the sample directly; "placebo"/"falsification" are never
#          written in table text (table-notes-conventions.md Rule 9).
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
# Outputs:
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2placebo.tex
#   output/reg/2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2placebo.tex
#   output/reg/h2_snsv_d12_k2placebo.tex
#   output/reg/h3_inf_formal_d12_k2placebo.tex
# Author: EK  Date: 2026-09-14
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

plac_dat <- build_k2_panel("placebo")

FE_TWO <- c("PWSID + year", "PWSID + year + STATE_CODE^year")
fe_state_yr <- "PWSID + year + STATE_CODE^year"

sample_clause <- paste0(
  "utilities with a coal mine within two flow steps downstream of their intake and no ",
  "coal mine upstream"
)

# Terminal-only diagnostic: placebo first-stage F. A null placebo result
# under a weak placebo first stage is uninformative, not a pass (plan Step 5).
f_plac <- f_clustered(plac_dat, fe_state_yr)
cat(sprintf("\nPlacebo first-stage F (state x year FE): %.2f [want ~53.53]\n", f_plac))
stopifnot(abs(f_plac - 53.53) < 0.01)
if (f_plac < 10) {
  cat("WARNING: placebo first stage is WEAK (F < 10) -- placebo nulls below are UNINFORMATIVE, not a pass.\n")
} else {
  cat("Placebo first-stage F gate PASSED (F >= 10) -- placebo nulls below are informative.\n")
}

depvar_vio <- paste0(
  "Dependent variable equals 1 if the utility had a violation of that type during the ",
  "year, 0 otherwise; coefficients and standard errors are multiplied by 100 to show ",
  "percentage point change. The instrument interacts an indicator for the post-1995 ",
  "period with the average coal sulfur content of watersheds within two flow steps ",
  "downstream of the utility's intake. The sample is ", sample_clause, "."
)

# ── MR violations ─────────────────────────────────────────────────────────
r_mr <- render_panel_k2(
  dat        = plac_dat,
  outcomes   = c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic",
                 inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  title      = paste0("Effect of coal mines on inorganic chemical violations at ", sample_clause),
  label      = "tab:2sls_dwnstrm_minevio_mr_ivsum_binvio_k2placebo",
  outfile    = "2sls_dwnstrm_minevio_mr_ivsum_binvio_k2placebo",
  depvar_sentence = depvar_vio,
  superheader = "Monitoring and reporting (MR) violation"
)

# Anchor check: all three placebo MR outcomes null under state x year FE,
# matching the grid log (p = .21, .46, .33) under the A2 intake-purity
# sample (a2-intake-purity-sample-pipeline.md).
p_nit <- get_term(r_mr$iv_list[[2]], "num_coal_mines_linked_sum")$pval
p_ars <- get_term(r_mr$iv_list[[4]], "num_coal_mines_linked_sum")$pval
p_ioc <- get_term(r_mr$iv_list[[6]], "num_coal_mines_linked_sum")$pval
cat(sprintf("\nPlacebo MR p-values (state x year FE): nitrates %.2f [want ~.21], arsenic %.2f [want ~.46], inorganic %.2f [want ~.33]\n",
            p_nit, p_ars, p_ioc))
stopifnot(p_nit > 0.1, p_ars > 0.1, p_ioc > 0.1)
cat("Placebo MR null gate PASSED (all p > 0.1).\n")

# ── MCL violations ────────────────────────────────────────────────────────
render_panel_k2(
  dat        = plac_dat,
  outcomes   = c(nitrates_MCL_bin = "Nitrates", arsenic_MCL_bin = "Arsenic",
                 inorganic_chemicals_MCL_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  title      = paste0("Effect of coal mines on inorganic chemical violations at ", sample_clause),
  label      = "tab:2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2placebo",
  outfile    = "2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2placebo",
  depvar_sentence = depvar_vio,
  superheader = "Maximum contaminant level (MCL) violation"
)

# ── Visit types ────────────────────────────────────────────────────────────
depvar_visit <- paste0(
  "Dependent variable equals 1 if the utility received a regulator visit of that type ",
  "during the year, 0 otherwise; coefficients and standard errors are multiplied by 100 ",
  "to show percentage point change. The instrument interacts an indicator for the ",
  "post-1995 period with the average coal sulfur content of watersheds within two flow ",
  "steps downstream of the utility's intake. The sample is ", sample_clause, "."
)
render_panel_k2(
  dat        = plac_dat,
  outcomes   = c(any_snsv = "Sanitary", any_tech = "Technical assistance",
                 any_enfvisit = "Enforcement", any_smpl = "Sample collection",
                 any_insp = "Inspection"),
  fe_specs   = fe_state_yr,
  dict       = k2_dict,
  title      = paste0("Effect of coal mining on regulator visit probability by visit type at ", sample_clause),
  label      = "tab:h2_snsv_d12_k2placebo",
  outfile    = "h2_snsv_d12_k2placebo",
  depvar_sentence = depvar_visit
)

# ── Enforcement types ───────────────────────────────────────────────────────
depvar_enf <- paste0(
  "Dependent variable equals 1 if the utility had an enforcement action of that type ",
  "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise; ",
  "coefficients and standard errors are multiplied by 100 to show percentage point ",
  "change. The instrument interacts an indicator for the post-1995 period with the ",
  "average coal sulfur content of watersheds within two flow steps downstream of the ",
  "utility's intake. The sample is ", sample_clause, "."
)
render_panel_k2(
  dat        = plac_dat,
  outcomes   = c(any_informal = "Informal", any_formal = "Formal", no_enf = "None"),
  fe_specs   = fe_state_yr,
  dict       = k2_dict,
  title      = paste0("Effect of coal mining on enforcement actions by type at ", sample_clause),
  label      = "tab:h3_inf_formal_d12_k2placebo",
  outfile    = "h3_inf_formal_d12_k2placebo",
  depvar_sentence = depvar_enf,
  superheader = "Any enforcement"
)

cat("\n=== run_k2_placebo_tables.r DONE ===\n")
