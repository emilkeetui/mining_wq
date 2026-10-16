# ============================================================
# Script: run_k2_main_tables.r
# Purpose: Main-arm k=2 A-full step-instrument-grid tables for main.tex:
#          any-category/MR/MCL binary-violation 2SLS panels, first stage,
#          exclusion-restriction falsification test, and visit-type /
#          enforcement-type panels. Sources k2_common.r. Read-only against
#          the k2 panel inputs; writes only new `_k2`-suffixed files under
#          output/reg/.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
# Outputs:
#   output/reg/2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2.tex (+ _present.tex)
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2.tex (+ _present.tex)
#   output/reg/2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2.tex (+ _present.tex)
#   output/reg/fs_dwnstrm_minevio_ivsum_k2.tex (+ _present.tex)
#   output/reg/exclusion_test_num_facilities_k2.tex (+ _present.tex)
#   output/reg/h2_snsv_d12_k2.tex (+ _present.tex)
#   output/reg/h3_inf_formal_d12_k2.tex (+ _present.tex)
#   With WQ_SAMPLE=step23 or step2 (k2_common.r): only the 2sls allcat/mr/mcl, h2 and
#   h3 tables, written with suffix `_step23`/`_step2` (+ _present.tex); 4.4-4.5 skipped.
# Author: EK  Date: 2026-09-14
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

main_dat <- build_k2_panel("main")

# Stable sample across FE specs: drop utilities the state x year FE cannot
# identify -- missing state code, or the only utility in their state (every
# state-year cell is a singleton, so fixest would drop them from the
# state x year columns only).
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

FE_TWO <- c("PWSID + year", "PWSID + STATE_CODE^year")
# Used by 4.4 and 4.6; defined here so 4.6 still runs when 4.4 is skipped (step23).
fe_state_yr <- "PWSID + STATE_CODE^year"

# Treatment definition shared by every note sentence (the endogenous regressor).
treat_sentence <- paste0(
  "Upstream coal mines is the number of active coal mines in watersheds ",
  if (IS_NEAREST) STEP_PHRASE else "within two flow steps",
  " upstream of the utility's intake, summed across those watersheds. "
)

# step23 mode: instrument + sample clauses shared by every note sentence.
instr_sample_step23 <- paste0(
  treat_sentence,
  "The instrument interacts an indicator for the post-1995 period with the average ",
  "coal sulfur content of watersheds within ", INSTR_STEP_PHRASE, " flow steps upstream of the utility's ",
  "intake. The sample is ", SAMPLE_DESC_NEAREST, ", in states with at least one other ",
  "such utility."
)

depvar_vio <- if (IS_NEAREST) paste0(
  "Dependent variable equals 1 if the utility had a violation of that type during the ",
  "year, 0 otherwise; coefficients and standard errors are multiplied by 100 to show ",
  "percentage point change. ", instr_sample_step23
) else paste0(
  "Dependent variable equals 1 if the utility had a violation of that type during the ",
  "year, 0 otherwise; coefficients and standard errors are multiplied by 100 to show ",
  "percentage point change. ", treat_sentence, "The instrument interacts an indicator for the post-1995 ",
  "period with the average coal sulfur content of watersheds within two flow steps ",
  "upstream of the utility's intake. The sample is utilities with a coal mine within ",
  "two flow steps upstream of their intake and no coal mine colocated with their intake, ",
  "in states with at least one other such utility."
)

# Notes variants for the compact-layout tables: treatment definition only (no
# instrument or sample sentences). step23 keeps its full sentences.
pp_sentence <- paste0("coefficients and standard errors are multiplied by 100 to show ",
                      "percentage point change. ")
depvar_vio_short <- if (IS_NEAREST) depvar_vio else paste0(
  "Dependent variable equals 1 if the utility had a violation of that type during the ",
  "year, 0 otherwise; ", pp_sentence, trimws(treat_sentence)
)

# Presentation companions: same table bodies, notes stripped to clustering +
# stars only (all render_panel_k2 outputs already show FE checkmark rows in
# panel_rf) -- .claude/logs/2026-08-31-presentation-notes-tables.md.
notes_present_panel <- "\\textit{Notes:} Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."

# ── 4.1 Any-category violations ──────────────────────────────────────────
render_panel_k2(
  dat        = main_dat,
  outcomes   = c(nitrates_bin = "Nitrates", arsenic_bin = "Arsenic",
                 inorganic_chemicals_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  title      = "Effect of coal mines on inorganic chemical violations at utilities",
  label      = paste0("tab:2sls_dwnstrm_minevio_allcat_ivsum_binvio", SFX),
  outfile    = paste0("2sls_dwnstrm_minevio_allcat_ivsum_binvio", SFX),
  depvar_sentence = depvar_vio_short,
  compact_layout = TRUE,
  superheader = "Any violation",
  notes_present = notes_present_panel
)

# ── 4.2 MR violations ────────────────────────────────────────────────────
r42 <- render_panel_k2(
  dat        = main_dat,
  outcomes   = c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic",
                 inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  title      = "Effect of coal mines on inorganic chemical violations at utilities",
  label      = paste0("tab:2sls_dwnstrm_minevio_mr_ivsum_binvio", SFX),
  outfile    = paste0("2sls_dwnstrm_minevio_mr_ivsum_binvio", SFX),
  depvar_sentence = depvar_vio_short,
  compact_layout = TRUE,
  superheader = "Monitoring and reporting (MR) violation",
  notes_present = notes_present_panel
)

# Anchor check (plan Step 4.2): state x year FE columns are 2, 4, 6 (2nd FE
# spec per outcome, outcome-major order). Must match the grid log to 2
# decimals or the panel build has diverged from run_step_instrument_grid.r.
# Anchors are k2-sample values, so the gate is skipped in step23 mode.
if (!IS_NEAREST) {
anchor_terms <- get_term(r42$iv_list[[2]], "num_coal_mines_linked_sum")  # nitrates, state x year
anchor_ars   <- get_term(r42$iv_list[[4]], "num_coal_mines_linked_sum")  # arsenic, state x year
anchor_ioc   <- get_term(r42$iv_list[[6]], "num_coal_mines_linked_sum")  # inorganic, state x year
cat(sprintf("\nAnchor check (state x year FE): nitrates %.2f (%.2f) [want 3.94 (1.75)]\n",
            anchor_terms$est, anchor_terms$se))
cat(sprintf("Anchor check (state x year FE): arsenic %.2f (%.2f) [want 3.78 (1.55)]\n",
            anchor_ars$est, anchor_ars$se))
cat(sprintf("Anchor check (state x year FE): inorganic %.2f (%.2f) [want 3.06 (1.66)]\n",
            anchor_ioc$est, anchor_ioc$se))
stopifnot(
  abs(round(anchor_terms$est, 2) - 3.94) < 0.01, abs(round(anchor_terms$se, 2) - 1.75) < 0.01,
  abs(round(anchor_ars$est, 2)   - 3.78) < 0.01, abs(round(anchor_ars$se, 2)   - 1.55) < 0.01,
  abs(round(anchor_ioc$est, 2)   - 3.06) < 0.01, abs(round(anchor_ioc$se, 2)   - 1.66) < 0.01
)
cat("MR anchor gate PASSED.\n")
}

# Stable-sample gate: every column (utility+year and state x year alike)
# must share the same N now that the unidentified utilities are screened
# out up front.
stopifnot(length(unique(r42$n_obs)) == 1, length(unique(r42$n_utils)) == 1)
cat(sprintf("MR stable-sample gate PASSED: %s utilities / %s obs in every column.\n",
            format(r42$n_utils[1], big.mark = ","), format(r42$n_obs[1], big.mark = ",")))

# ── 4.3 MCL violations ───────────────────────────────────────────────────
render_panel_k2(
  dat        = main_dat,
  outcomes   = c(nitrates_MCL_bin = "Nitrates", arsenic_MCL_bin = "Arsenic",
                 inorganic_chemicals_MCL_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  title      = "Effect of coal mines on inorganic chemical violations at utilities",
  label      = paste0("tab:2sls_dwnstrm_minevio_mcl_ivsum_binvio", SFX),
  outfile    = paste0("2sls_dwnstrm_minevio_mcl_ivsum_binvio", SFX),
  depvar_sentence = depvar_vio_short,
  compact_layout = TRUE,
  superheader = "Maximum contaminant level (MCL) violation",
  notes_present = notes_present_panel
)

# ── 4.4 First stage ───────────────────────────────────────────────────────
# 4.4 and 4.5 are not requested for the step23 sample (first-stage F still
# reported inside every render_panel_k2 table).
if (!IS_NEAREST) {
fs_m <- fixest::feols(
  num_coal_mines_linked_sum ~ post95:sulfur_mean0 + num_facilities | PWSID + STATE_CODE^year,
  data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE
)
f_val_main <- f_clustered(main_dat, fe_state_yr)
cat(sprintf("\nFirst-stage F (main, state x year FE): %.2f [want ~49.20]\n", f_val_main))
stopifnot(abs(f_val_main - 49.20) < 0.01)
cat("First-stage F gate PASSED.\n")

fs_label <- "Post-1995 $\\times$ Upstream sulfur \\%"
fs_notes_fn <- function(extra) notes_k2(paste0(
  "The dependent variable is the number of coal mines in watersheds within two flow ",
  "steps upstream of the utility's intake, summed across those watersheds."
), extra = extra, sample_period = FALSE)
render_coef_table_k2(
  rows        = list(list(label = fs_label, terms = list(get_term(fs_m, "post95:sulfur_mean0")))),
  col_headers = "Upstream coal mines (sum)", colnums = FALSE,
  fe_list     = list("Utility" = TRUE, "State $\\times$ year" = TRUE),
  f_rows      = list("First-stage F-statistic" = f_val_main),
  n_obs       = nobs(fs_m), n_utils = length(fixest::fixef(fs_m)$PWSID),
  label       = "tab:fs_dwnstrm_minevio_ivsum_k2",
  title       = "First stage: effect of the instrument on the number of upstream coal mines, 1985--2005",
  outfile     = "fs_dwnstrm_minevio_ivsum_k2",
  note_text_fn = fs_notes_fn, notes_present = notes_present_panel,
  data_w_cm   = 3
)

# ── 4.5 Exclusion-restriction falsification test ─────────────────────────
m1 <- fixest::feols(num_facilities ~ post95:sulfur_mean0 | PWSID + STATE_CODE^year,
                     data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)

n_years_expected <- length(unique(main_dat$year))
year_counts <- main_dat %>% dplyr::group_by(PWSID) %>%
  dplyr::summarise(n_years = dplyr::n_distinct(year), .groups = "drop")
balanced_ids <- year_counts$PWSID[year_counts$n_years == n_years_expected]
dat_bal <- main_dat[main_dat$PWSID %in% balanced_ids, ]
cat(sprintf("Balanced-panel subsample: %d utilities (of %d), %d obs\n",
            length(balanced_ids), dplyr::n_distinct(main_dat$PWSID), nrow(dat_bal)))

m2 <- fixest::feols(num_facilities ~ sulfur_mean0 + post95:sulfur_mean0 | year,
                     data = dat_bal, cluster = ~PWSID, warn = FALSE, notes = FALSE)

get_single_term <- function(model, include, exclude = NULL) {
  ct <- fixest::coeftable(model)
  rn <- rownames(ct)
  ok <- sapply(rn, function(r) {
    all(sapply(include, function(p) grepl(p, r, fixed = TRUE))) &&
      (is.null(exclude) || !any(sapply(exclude, function(p) grepl(p, r, fixed = TRUE))))
  })
  row <- rn[ok]
  if (length(row) != 1) {
    stop("Could not uniquely resolve term for include=[", paste(include, collapse = ","),
         "] exclude=[", paste(exclude, collapse = ","), "] - candidate rows: ",
         paste(row, collapse = " | "), " - all rows: ", paste(rn, collapse = " | "))
  }
  list(est = ct[row, "Estimate"], se = ct[row, "Std. Error"], pval = ct[row, "Pr(>|t|)"], row = row)
}

col1_interact <- get_single_term(m1, include = c("post95", "sulfur_mean0"))
col2_main     <- get_single_term(m2, include = c("sulfur_mean0"), exclude = c("post95"))
col2_interact <- get_single_term(m2, include = c("post95", "sulfur_mean0"))

note_et_fn <- function(extra) notes_k2(paste0(
  "The dependent variable is the number of active intake facilities operated by the ",
  "utility in that year. The sample is utilities with a coal mine within two flow ",
  "steps upstream of their intake and no coal mine colocated with their intake, in ",
  "states with at least one other such utility."
), extra = extra)
render_coef_table_k2(
  rows = list(
    list(label = "Upstream sulfur \\%", terms = list(NULL, col2_main)),
    list(label = fs_label, terms = list(col1_interact, col2_interact))
  ),
  col_headers = c("", ""), superheader = "Number of intake facilities",
  fe_list     = list("Utility" = c(TRUE, FALSE), "Year" = c(FALSE, TRUE), "State $\\times$ year" = c(TRUE, FALSE)),
  spec_rows   = list("Balanced panel" = c(FALSE, TRUE)),
  n_obs       = c(nobs(m1), nobs(m2)),
  n_utils     = c(length(fixest::fixef(m1)$PWSID), length(balanced_ids)),
  label       = "tab:exclusion_test_num_facilities_k2",
  title       = "Effect of instrument on utility characteristics",
  outfile     = "exclusion_test_num_facilities_k2",
  note_text_fn = note_et_fn, notes_present = notes_present_panel
)
}  # end !IS_NEAREST (4.4-4.5)

# ── 4.6 Visit types ────────────────────────────────────────────────────────
depvar_visit <- if (IS_NEAREST) paste0(
  "Dependent variable equals 1 if the utility received a regulator visit of that type ",
  "during the year, 0 otherwise; coefficients and standard errors are multiplied by 100 ",
  "to show percentage point change. ", instr_sample_step23
) else paste0(
  "Dependent variable equals 1 if the utility received a regulator visit of that type ",
  "during the year, 0 otherwise; coefficients and standard errors are multiplied by 100 ",
  "to show percentage point change. ", treat_sentence, "The instrument interacts an indicator for the ",
  "post-1995 period with the average coal sulfur content of watersheds within two flow ",
  "steps upstream of the utility's intake. The sample is utilities with a coal mine ",
  "within two flow steps upstream of their intake and no coal mine colocated with their ",
  "intake, in states with at least one other such utility."
)
depvar_visit_short <- if (IS_NEAREST) depvar_visit else paste0(
  "Dependent variable equals 1 if the utility received a regulator visit of that type ",
  "during the year, 0 otherwise; ", pp_sentence, trimws(treat_sentence)
)
render_panel_k2(
  dat        = main_dat,
  outcomes   = c(any_snsv = "Sanitary", any_tech = "Technical assistance",
                 any_enfvisit = "Enforcement", any_smpl = "Sample collection",
                 any_insp = "Inspection"),
  fe_specs   = fe_state_yr,
  dict       = k2_dict,
  title      = "Effect of coal mining on regulator visit probability by visit type",
  label      = paste0("tab:h2_snsv_d12", SFX),
  outfile    = paste0("h2_snsv_d12", SFX),
  depvar_sentence = depvar_visit_short,
  compact_layout = TRUE,
  notes_present = notes_present_panel
)

# ── 4.7 Enforcement types ──────────────────────────────────────────────────
depvar_enf <- if (IS_NEAREST) paste0(
  "Dependent variable equals 1 if the utility had an enforcement action of that type ",
  "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise; ",
  "coefficients and standard errors are multiplied by 100 to show percentage point ",
  "change. ", instr_sample_step23
) else paste0(
  "Dependent variable equals 1 if the utility had an enforcement action of that type ",
  "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise; ",
  "coefficients and standard errors are multiplied by 100 to show percentage point ",
  "change. ", treat_sentence, "The instrument interacts an indicator for the post-1995 period with the ",
  "average coal sulfur content of watersheds within two flow steps upstream of the ",
  "utility's intake. The sample is utilities with a coal mine within two flow steps ",
  "upstream of their intake and no coal mine colocated with their intake, in states ",
  "with at least one other such utility."
)
depvar_enf_short <- if (IS_NEAREST) depvar_enf else paste0(
  "Dependent variable equals 1 if the utility had an enforcement action of that type ",
  "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise; ",
  pp_sentence, trimws(treat_sentence)
)
r47 <- render_panel_k2(
  dat        = main_dat,
  outcomes   = c(any_informal = "Informal", any_formal = "Formal", no_enf = "None"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  title      = "Effect of coal mining on enforcement actions by type",
  label      = paste0("tab:h3_inf_formal_d12", SFX),
  outfile    = paste0("h3_inf_formal_d12", SFX),
  depvar_sentence = depvar_enf_short,
  compact_layout = TRUE,
  superheader = "Enforcement",
  notes_present = notes_present_panel
)

stopifnot(length(unique(r47$n_obs)) == 1, length(unique(r47$n_utils)) == 1)
cat(sprintf("Enforcement stable-sample gate PASSED: %s utilities / %s obs in every column.\n",
            format(r47$n_utils[1], big.mark = ","), format(r47$n_obs[1], big.mark = ",")))

cat("\n=== run_k2_main_tables.r DONE ===\n")
