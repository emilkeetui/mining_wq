# ============================================================
# Script: run_k2_annprod_tables.r
# Purpose: Regressor-swap versions of the main-arm k=2 tables: the
#          any-category/MR/MCL binary-violation 2SLS panels, first stage,
#          and visit-type / enforcement-type panels of run_k2_main_tables.r,
#          re-estimated with annual upstream coal production (1M short tons,
#          summed over watersheds within two flow steps upstream) as the
#          endogenous regressor in place of the upstream mine count. Same
#          sample, fixed effects, instrument and layout. Sources k2_common.r.
#          Writes only new `_k2annprod`-suffixed files under output/reg/.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2.tex (read-only, N gate)
# Outputs:
#   output/reg/2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2annprod.tex (+ _present.tex)
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2annprod.tex (+ _present.tex)
#   output/reg/2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2annprod.tex (+ _present.tex)
#   output/reg/fs_dwnstrm_minevio_ivsum_k2annprod.tex (+ _present.tex)
#   output/reg/h2_snsv_d12_k2annprod.tex (+ _present.tex)
#   output/reg/h3_inf_formal_d12_k2annprod.tex (+ _present.tex)
# Author: EK  Date: 2026-09-23
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

main_dat <- build_k2_panel("main")

# Stable sample across FE specs (verbatim from run_k2_main_tables.r): drop
# utilities the state x year FE cannot identify -- missing state code, or the
# only utility in their state.
lone_states <- main_dat %>%
  dplyr::filter(!is.na(STATE_CODE)) %>%
  dplyr::group_by(STATE_CODE) %>%
  dplyr::summarise(n_util = dplyr::n_distinct(PWSID), .groups = "drop") %>%
  dplyr::filter(n_util == 1) %>%
  dplyr::pull(STATE_CODE)
n_util_before <- dplyr::n_distinct(main_dat$PWSID); n_obs_before <- nrow(main_dat)
main_dat <- main_dat %>% dplyr::filter(!is.na(STATE_CODE), !(STATE_CODE %in% lone_states))
cat(sprintf("Stable-sample screen: dropped %d utilities / %d obs (lone-state: %s; missing state)\n",
            n_util_before - dplyr::n_distinct(main_dat$PWSID), n_obs_before - nrow(main_dat),
            paste(lone_states, collapse = ", ")))

# Annual upstream production in 1M short tons (NA -> 0, i.e. no linked output
# that year, matching the zero-fill in run_k2_6yr_tables.r's dose builder).
main_dat$coal_prod_upstream_1mst <- replace(main_dat$production_linked_sum,
                                            is.na(main_dat$production_linked_sum), 0) / 1e6
cat(sprintf("Annual upstream production (1M ST): mean %.3f, max %.3f, share zero %.3f, NA filled %d\n",
            mean(main_dat$coal_prod_upstream_1mst), max(main_dat$coal_prod_upstream_1mst),
            mean(main_dat$coal_prod_upstream_1mst == 0), sum(is.na(main_dat$production_linked_sum))))

COALVAR <- "coal_prod_upstream_1mst"
FE_TWO  <- c("PWSID + year", "PWSID + STATE_CODE^year")

# Shared sentences: the regressor description and the sample description.
regressor_sentence <- paste0(
  "The endogenous regressor is coal production during the year, in millions of short ",
  "tons, in watersheds within two flow steps upstream of the utility's intake."
)
sample_sentence <- paste0(
  "The sample is utilities with a coal mine within two flow steps upstream of their ",
  "intake and no coal mine colocated with their intake, in states with at least one ",
  "other such utility."
)
instr_sentence <- paste0(
  "The instrument interacts an indicator for the post-1995 period with the average ",
  "coal sulfur content of watersheds within two flow steps upstream of the utility's intake."
)

depvar_vio <- paste(
  "Dependent variable equals 1 if the utility had a violation of that type during the",
  "year, 0 otherwise; coefficients and standard errors are multiplied by 100 to show",
  "percentage point change.", regressor_sentence, instr_sentence, sample_sentence
)

notes_present_panel <- "\\textit{Notes:} Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."

# N of the parent mine-count MR table (same sample) for the stable-sample gate.
parent_obs_line <- grep("^Observations &", readLines(file.path(ROOT, "output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2.tex")), value = TRUE)
parent_n_obs    <- unique(as.integer(gsub("[^0-9]", "", trimws(strsplit(sub("^Observations &", "", sub("\\\\\\\\.*$", "", parent_obs_line)), "&")[[1]]))))
stopifnot(length(parent_n_obs) == 1)

check_stable <- function(r, tag, want_n = NULL) {
  stopifnot(length(unique(r$n_obs)) == 1, length(unique(r$n_utils)) == 1)
  if (!is.null(want_n)) stopifnot(r$n_obs[1] == want_n)
  cat(sprintf("%s stable-sample gate PASSED: %s utilities / %s obs in every column. F: %s\n",
              tag, format(r$n_utils[1], big.mark = ","), format(r$n_obs[1], big.mark = ","),
              paste(fmt_single(r$f_vals), collapse = ", ")))
  if (any(r$f_vals < 10)) cat(sprintf("  WARNING: %s first-stage F below 10 in at least one column.\n", tag))
  iv_signs <- vapply(r$iv_list, function(m) get_term(m, COALVAR)$est, numeric(1))
  cat(sprintf("  %s 2SLS coefficients: %s\n", tag, paste(sprintf("%.3f", iv_signs), collapse = ", ")))
}

# ── 1. Any-category violations ───────────────────────────────────────────
r1 <- render_panel_k2(
  dat        = main_dat,
  outcomes   = c(nitrates_bin = "Nitrates", arsenic_bin = "Arsenic",
                 inorganic_chemicals_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  coalvar    = COALVAR,
  title      = "Effect of upstream coal production on inorganic chemical violations at utilities",
  label      = "tab:2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2annprod",
  outfile    = "2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2annprod",
  depvar_sentence = depvar_vio,
  superheader = "Any violation",
  notes_present = notes_present_panel
)
check_stable(r1, "Any-category", parent_n_obs)

# ── 2. MR violations ─────────────────────────────────────────────────────
r2 <- render_panel_k2(
  dat        = main_dat,
  outcomes   = c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic",
                 inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  coalvar    = COALVAR,
  title      = "Effect of upstream coal production on inorganic chemical violations at utilities",
  label      = "tab:2sls_dwnstrm_minevio_mr_ivsum_binvio_k2annprod",
  outfile    = "2sls_dwnstrm_minevio_mr_ivsum_binvio_k2annprod",
  depvar_sentence = depvar_vio,
  superheader = "Monitoring and reporting (MR) violation",
  notes_present = notes_present_panel
)
check_stable(r2, "MR", parent_n_obs)

# ── 3. MCL violations ────────────────────────────────────────────────────
r3 <- render_panel_k2(
  dat        = main_dat,
  outcomes   = c(nitrates_MCL_bin = "Nitrates", arsenic_MCL_bin = "Arsenic",
                 inorganic_chemicals_MCL_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  coalvar    = COALVAR,
  title      = "Effect of upstream coal production on inorganic chemical violations at utilities",
  label      = "tab:2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2annprod",
  outfile    = "2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2annprod",
  depvar_sentence = depvar_vio,
  superheader = "Maximum contaminant level (MCL) violation",
  notes_present = notes_present_panel
)
check_stable(r3, "MCL", parent_n_obs)

# ── 4. First stage ───────────────────────────────────────────────────────
fe_state_yr <- "PWSID + STATE_CODE^year"
fs_m <- fixest::feols(
  coal_prod_upstream_1mst ~ post95:sulfur_mean0 + num_facilities | PWSID + STATE_CODE^year,
  data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE
)
f_val_main <- f_clustered(main_dat, fe_state_yr, endog = COALVAR)
fs_term <- get_term(fs_m, "post95:sulfur_mean0")
cat(sprintf("\nFirst stage (annual prod., state x year FE): coef %.4f (%.4f), F = %.2f\n",
            fs_term$est, fs_term$se, f_val_main))
if (f_val_main < 10) cat("  WARNING: first-stage F below 10.\n")

fs_title <- "First stage: effect of the Acid Rain Program on upstream coal production (watersheds within two flow steps upstream)"
el_fs <- list(
  "F-test (1st stage, clustered)"      = fmt_single(f_val_main),
  "Utility fixed effects"              = "$\\checkmark$",
  "State $\\times$ year fixed effects" = "$\\checkmark$"
)
fs_notes <- notes_k2(paste(
  "The dependent variable is coal production during the year, in millions of short",
  "tons, in watersheds within two flow steps upstream of the utility's intake. The",
  "instrument interacts an indicator for the post-1995 period with the average coal",
  "sulfur content of those watersheds.", sample_sentence
))
write_fs <- function(notes, file) {
  etable(
    fs_m,
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    digits          = "r4",
    drop            = "Number of intake facilities",
    drop.section    = "fixef",
    title           = fs_title,
    label           = "tab:fs_dwnstrm_minevio_ivsum_k2annprod",
    extralines      = el_fs,
    fitstat         = ~ n,
    dict            = k2_dict,
    notes           = notes,
    postprocess.tex = function(x) right_align_tabular(move_notes_below_adjustbox(x)),
    file            = file
  )
  cat("  Written:", file, "\n")
}
write_fs(fs_notes,            file.path(ROOT, "output/reg/fs_dwnstrm_minevio_ivsum_k2annprod.tex"))
write_fs(notes_present_panel, file.path(ROOT, "output/reg/fs_dwnstrm_minevio_ivsum_k2annprod_present.tex"))

# ── 5. Visit types ───────────────────────────────────────────────────────
depvar_visit <- paste(
  "Dependent variable equals 1 if the utility received a regulator visit of that type",
  "during the year, 0 otherwise; coefficients and standard errors are multiplied by 100",
  "to show percentage point change.", regressor_sentence, instr_sentence, sample_sentence
)
r5 <- render_panel_k2(
  dat        = main_dat,
  outcomes   = c(any_snsv = "Sanitary", any_tech = "Technical assistance",
                 any_enfvisit = "Enforcement", any_smpl = "Sample collection",
                 any_insp = "Inspection"),
  fe_specs   = fe_state_yr,
  dict       = k2_dict,
  coalvar    = COALVAR,
  title      = "Effect of upstream coal production on regulator visit probability by visit type",
  label      = "tab:h2_snsv_d12_k2annprod",
  outfile    = "h2_snsv_d12_k2annprod",
  depvar_sentence = depvar_visit,
  notes_present = notes_present_panel
)
check_stable(r5, "Visit")

# ── 6. Enforcement types ─────────────────────────────────────────────────
depvar_enf <- paste(
  "Dependent variable equals 1 if the utility had an enforcement action of that type",
  "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise;",
  "coefficients and standard errors are multiplied by 100 to show percentage point",
  "change.", regressor_sentence, instr_sentence, sample_sentence
)
r6 <- render_panel_k2(
  dat        = main_dat,
  outcomes   = c(any_informal = "Informal", any_formal = "Formal", no_enf = "None"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  coalvar    = COALVAR,
  title      = "Effect of upstream coal production on enforcement actions by type",
  label      = "tab:h3_inf_formal_d12_k2annprod",
  outfile    = "h3_inf_formal_d12_k2annprod",
  depvar_sentence = depvar_enf,
  superheader = "Enforcement",
  notes_present = notes_present_panel
)
check_stable(r6, "Enforcement")

cat("\n=== run_k2_annprod_tables.r DONE ===\n")
