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
# Author: EK  Date: 2026-09-14
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

main_dat <- build_k2_panel("main")

FE_TWO <- c("PWSID + year", "PWSID + year + STATE_CODE^year")

depvar_vio <- paste0(
  "Dependent variable equals 1 if the utility had a violation of that type during the ",
  "year, 0 otherwise; coefficients and standard errors are multiplied by 100 to show ",
  "percentage point change. The instrument interacts an indicator for the post-1995 ",
  "period with the average coal sulfur content of watersheds within two flow steps ",
  "upstream of the utility's intake. The sample is utilities with a coal mine within ",
  "two flow steps upstream of their intake and no coal mine colocated with their intake."
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
  label      = "tab:2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2",
  outfile    = "2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2",
  depvar_sentence = depvar_vio,
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
  label      = "tab:2sls_dwnstrm_minevio_mr_ivsum_binvio_k2",
  outfile    = "2sls_dwnstrm_minevio_mr_ivsum_binvio_k2",
  depvar_sentence = depvar_vio,
  superheader = "Monitoring and reporting (MR) violation",
  notes_present = notes_present_panel
)

# Anchor check (plan Step 4.2): state x year FE columns are 2, 4, 6 (2nd FE
# spec per outcome, outcome-major order). Must match the grid log to 2
# decimals or the panel build has diverged from run_step_instrument_grid.r.
anchor_terms <- get_term(r42$iv_list[[2]], "num_coal_mines_linked_sum")  # nitrates, state x year
anchor_ars   <- get_term(r42$iv_list[[4]], "num_coal_mines_linked_sum")  # arsenic, state x year
anchor_ioc   <- get_term(r42$iv_list[[6]], "num_coal_mines_linked_sum")  # inorganic, state x year
cat(sprintf("\nAnchor check (state x year FE): nitrates %.2f (%.2f) [want 3.94 (1.75)]\n",
            anchor_terms$est, anchor_terms$se))
cat(sprintf("Anchor check (state x year FE): arsenic %.2f (%.2f) [want 3.78 (1.56)]\n",
            anchor_ars$est, anchor_ars$se))
cat(sprintf("Anchor check (state x year FE): inorganic %.2f (%.2f) [want 3.06 (1.66)]\n",
            anchor_ioc$est, anchor_ioc$se))
stopifnot(
  abs(round(anchor_terms$est, 2) - 3.94) < 0.01, abs(round(anchor_terms$se, 2) - 1.75) < 0.01,
  abs(round(anchor_ars$est, 2)   - 3.78) < 0.01, abs(round(anchor_ars$se, 2)   - 1.56) < 0.01,
  abs(round(anchor_ioc$est, 2)   - 3.06) < 0.01, abs(round(anchor_ioc$se, 2)   - 1.66) < 0.01
)
cat("MR anchor gate PASSED.\n")

# ── 4.3 MCL violations ───────────────────────────────────────────────────
render_panel_k2(
  dat        = main_dat,
  outcomes   = c(nitrates_MCL_bin = "Nitrates", arsenic_MCL_bin = "Arsenic",
                 inorganic_chemicals_MCL_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  title      = "Effect of coal mines on inorganic chemical violations at utilities",
  label      = "tab:2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2",
  outfile    = "2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2",
  depvar_sentence = depvar_vio,
  superheader = "Maximum contaminant level (MCL) violation",
  notes_present = notes_present_panel
)

# ── 4.4 First stage ───────────────────────────────────────────────────────
fe_state_yr <- "PWSID + year + STATE_CODE^year"
fs_m <- fixest::feols(
  num_coal_mines_linked_sum ~ post95:sulfur_mean0 + num_facilities | PWSID + year + STATE_CODE^year,
  data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE
)
f_val_main <- f_clustered(main_dat, fe_state_yr)
cat(sprintf("\nFirst-stage F (main, state x year FE): %.2f [want ~49.10]\n", f_val_main))
stopifnot(abs(f_val_main - 49.10) < 0.01)
cat("First-stage F gate PASSED.\n")

el_fs <- list(
  "F-test (1st stage, clustered)"      = fmt_single(f_val_main),
  "Utility fixed effects"              = "$\\checkmark$",
  "Year fixed effects"                 = "$\\checkmark$",
  "State $\\times$ year fixed effects" = "$\\checkmark$"
)
fs_notes <- notes_k2(paste0(
  "The dependent variable is the number of coal mines in watersheds within two flow ",
  "steps upstream of the utility's intake, summed across those watersheds. The ",
  "instrument interacts an indicator for the post-1995 period with the average coal ",
  "sulfur content of those watersheds. The sample is utilities with a coal mine ",
  "within two flow steps upstream of their intake and no coal mine colocated with ",
  "their intake."
))
etable(
  fs_m,
  style.tex       = style.tex("aer", adjustbox = TRUE),
  tex             = TRUE,
  digits          = "r4",
  drop            = "Number of intake facilities",
  drop.section    = "fixef",
  title           = "First stage: effect of the Acid Rain Program on the number of upstream coal mines (summed across watersheds within two flow steps upstream)",
  label           = "tab:fs_dwnstrm_minevio_ivsum_k2",
  extralines      = el_fs,
  dict            = k2_dict,
  notes           = fs_notes,
  postprocess.tex = function(x) right_align_tabular(move_notes_below_adjustbox(x)),
  file            = "Z:/ek559/mining_wq/output/reg/fs_dwnstrm_minevio_ivsum_k2.tex"
)
cat("  Written: output/reg/fs_dwnstrm_minevio_ivsum_k2.tex\n")

# Presentation companion: same table body, notes stripped to clustering +
# stars only (FE checkmark rows already shown via el_fs) --
# .claude/logs/2026-08-31-presentation-notes-tables.md.
etable(
  fs_m,
  style.tex       = style.tex("aer", adjustbox = TRUE),
  tex             = TRUE,
  digits          = "r4",
  drop            = "Number of intake facilities",
  drop.section    = "fixef",
  title           = "First stage: effect of the Acid Rain Program on the number of upstream coal mines (summed across watersheds within two flow steps upstream)",
  label           = "tab:fs_dwnstrm_minevio_ivsum_k2",
  extralines      = el_fs,
  dict            = k2_dict,
  notes           = notes_present_panel,
  postprocess.tex = function(x) right_align_tabular(move_notes_below_adjustbox(x)),
  file            = "Z:/ek559/mining_wq/output/reg/fs_dwnstrm_minevio_ivsum_k2_present.tex"
)
cat("  Written: output/reg/fs_dwnstrm_minevio_ivsum_k2_present.tex\n")

# ── 4.5 Exclusion-restriction falsification test ─────────────────────────
m1 <- fixest::feols(num_facilities ~ post95:sulfur_mean0 | PWSID + year + STATE_CODE^year,
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

DIGITS_ET <- 4
fmt_col_terms <- function(terms_list, digits = DIGITS_ET) {
  int_w <- function(x) {
    if (is.na(x)) return(0L)
    nchar(sub("\\..*$", "", sprintf(paste0("%.", digits, "f"), abs(x))))
  }
  w <- max(sapply(terms_list, function(t) max(int_w(t$est), int_w(t$se))))
  lapply(terms_list, function(t) fmt_num_wide(t$est, t$se, t$pval, w, digits))
}
col1_fmt <- fmt_col_terms(list(col1_interact))
col2_fmt <- fmt_col_terms(list(col2_main, col2_interact))

sulfur_row_coef   <- paste0("Upstream sulfur & & ", col2_fmt[[1]]$coef, " \\\\")
sulfur_row_se     <- paste0(" & & ", col2_fmt[[1]]$se, " \\\\")
interact_row_coef <- paste0("Post-1995 $\\times$ Upstream sulfur & ", col1_fmt[[1]]$coef, " & ", col2_fmt[[2]]$coef, " \\\\")
interact_row_se   <- paste0(" & ", col1_fmt[[1]]$se, " & ", col2_fmt[[2]]$se, " \\\\")

n_utils_col1 <- length(fixest::fixef(m1)$PWSID)
n_utils_col2 <- length(balanced_ids)
n_obs_col1   <- nobs(m1)
n_obs_col2   <- nobs(m2)

n_y_et <- 2
label_w_cm_et <- 5.5
data_w_cm_et  <- 2.5
col_spec_et <- paste0("p{", label_w_cm_et, "cm}",
                       paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w_cm_et, "cm}"), n_y_et), collapse = ""))
depvar_header_et <- " & \\multicolumn{2}{c}{Number of Intake Facilities} \\\\"
header_row_et <- " & \\multicolumn{1}{c}{(1)} & \\multicolumn{1}{c}{(2)} \\\\"

tabcolsep_pt <- 4
cm_per_pt    <- 2.54 / 72.27
textwidth_cm <- 16.51
intercol_pad_cm_et <- 2 * (n_y_et + 1) * tabcolsep_pt * cm_per_pt
natural_w_cm_et <- label_w_cm_et + n_y_et * data_w_cm_et + intercol_pad_cm_et
needs_scale_et  <- natural_w_cm_et > textwidth_cm
total_w_et <- if (needs_scale_et) "\\linewidth" else paste0(round(natural_w_cm_et, 4), "cm")

tabular_lines_et <- c(
  paste0("\\begin{tabular}{", col_spec_et, "}"),
  "\\toprule",
  depvar_header_et,
  header_row_et,
  "\\hline",
  sulfur_row_coef,
  sulfur_row_se,
  interact_row_coef,
  interact_row_se,
  "\\hline",
  "Utility fixed effects & $\\checkmark$ & \\\\",
  "Year fixed effects & $\\checkmark$ & $\\checkmark$ \\\\",
  "State $\\times$ year fixed effects & $\\checkmark$ & \\\\",
  "Balanced panel & & $\\checkmark$ \\\\",
  paste0("Utilities & ", format(n_utils_col1, big.mark = ","), " & ", format(n_utils_col2, big.mark = ","), " \\\\"),
  paste0("Observations & ", format(n_obs_col1, big.mark = ","), " & ", format(n_obs_col2, big.mark = ","), " \\\\"),
  "\\bottomrule",
  "\\end{tabular}"
)
if (needs_scale_et) {
  tab_start <- grep("^\\\\begin\\{tabular\\}", tabular_lines_et)[1]
  tab_end   <- max(grep("^\\\\end\\{tabular\\}", tabular_lines_et))
  tabular_lines_et <- c(
    tabular_lines_et[seq_len(tab_start - 1)],
    "\\begin{adjustbox}{max width=\\linewidth}",
    tabular_lines_et[tab_start:tab_end],
    "\\end{adjustbox}",
    if (tab_end < length(tabular_lines_et)) tabular_lines_et[(tab_end + 1):length(tabular_lines_et)] else NULL
  )
}

note_et <- notes_k2("The dependent variable is the number of active intake facilities operated by the utility in that year.")
table_lines_et <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  paste0("\\begin{minipage}{", total_w_et, "}"),
  paste0("\\caption{\\label{tab:exclusion_test_num_facilities_k2} Effect of instrument on utility characteristics}"),
  "\\end{minipage}",
  "\\small",
  "{\\setlength{\\tabcolsep}{4pt}%",
  tabular_lines_et,
  "}",
  paste0("\\begin{minipage}{", total_w_et, "}"),
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  note_et,
  "\\end{minipage}",
  "\\end{table}"
)
writeLines(table_lines_et, "Z:/ek559/mining_wq/output/reg/exclusion_test_num_facilities_k2.tex")
cat("  Written: output/reg/exclusion_test_num_facilities_k2.tex\n")

# Presentation companion: same table body, notes stripped to clustering +
# stars only (FE checkmark rows already shown in tabular_lines_et) --
# .claude/logs/2026-08-31-presentation-notes-tables.md.
table_lines_et_present <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  paste0("\\begin{minipage}{", total_w_et, "}"),
  paste0("\\caption{\\label{tab:exclusion_test_num_facilities_k2} Effect of instrument on utility characteristics}"),
  "\\end{minipage}",
  "\\small",
  "{\\setlength{\\tabcolsep}{4pt}%",
  tabular_lines_et,
  "}",
  paste0("\\begin{minipage}{", total_w_et, "}"),
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  notes_present_panel,
  "\\end{minipage}",
  "\\end{table}"
)
writeLines(table_lines_et_present, "Z:/ek559/mining_wq/output/reg/exclusion_test_num_facilities_k2_present.tex")
cat("  Written: output/reg/exclusion_test_num_facilities_k2_present.tex\n")

# ── 4.6 Visit types ────────────────────────────────────────────────────────
depvar_visit <- paste0(
  "Dependent variable equals 1 if the utility received a regulator visit of that type ",
  "during the year, 0 otherwise; coefficients and standard errors are multiplied by 100 ",
  "to show percentage point change. The instrument interacts an indicator for the ",
  "post-1995 period with the average coal sulfur content of watersheds within two flow ",
  "steps upstream of the utility's intake. The sample is utilities with a coal mine ",
  "within two flow steps upstream of their intake and no coal mine colocated with their ",
  "intake."
)
render_panel_k2(
  dat        = main_dat,
  outcomes   = c(any_snsv = "Sanitary", any_tech = "Technical assistance",
                 any_enfvisit = "Enforcement", any_smpl = "Sample collection",
                 any_insp = "Inspection"),
  fe_specs   = fe_state_yr,
  dict       = k2_dict,
  title      = "Effect of coal mining on regulator visit probability by visit type",
  label      = "tab:h2_snsv_d12_k2",
  outfile    = "h2_snsv_d12_k2",
  depvar_sentence = depvar_visit,
  notes_present = notes_present_panel
)

# ── 4.7 Enforcement types ──────────────────────────────────────────────────
depvar_enf <- paste0(
  "Dependent variable equals 1 if the utility had an enforcement action of that type ",
  "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise; ",
  "coefficients and standard errors are multiplied by 100 to show percentage point ",
  "change. The instrument interacts an indicator for the post-1995 period with the ",
  "average coal sulfur content of watersheds within two flow steps upstream of the ",
  "utility's intake. The sample is utilities with a coal mine within two flow steps ",
  "upstream of their intake and no coal mine colocated with their intake."
)
render_panel_k2(
  dat        = main_dat,
  outcomes   = c(any_informal = "Informal", any_formal = "Formal", no_enf = "None"),
  fe_specs   = FE_TWO,
  dict       = k2_dict,
  title      = "Effect of coal mining on enforcement actions by type",
  label      = "tab:h3_inf_formal_d12_k2",
  outfile    = "h3_inf_formal_d12_k2",
  depvar_sentence = depvar_enf,
  superheader = "Any enforcement",
  notes_present = notes_present_panel
)

cat("\n=== run_k2_main_tables.r DONE ===\n")
