# ============================================================
# Script: run_k2_updn_tables.r
# Purpose: Two-instrument k=2 2SLS: upstream AND downstream coal mines
#          (each summed over watersheds within two flow steps of the
#          intake) instrumented jointly by post95 x upstream sulfur and
#          post95 x downstream sulfur, on the exact sample of
#          2sls_dwnstrm_minevio_mr_ivsum_binvio_k2. Exclusion test: the
#          downstream 2SLS coefficient should be statistically zero if the
#          upstream-sulfur instrument is valid. Sources k2_common.r
#          (unchanged); writes only new `_k2updn`-suffixed files under
#          output/reg/.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (directly + via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/step_purity_flags.parquet (via k2_common.r)
# Outputs:
#   output/reg/fs_dwnstrm_minevio_ivsum_k2updn.tex (+ _present.tex)
#   output/reg/exclusion_test_num_facilities_k2updn.tex (+ _present.tex)
#   output/reg/2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2updn.tex (+ _present.tex)
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2updn.tex (+ _present.tex)
#   output/reg/2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2updn.tex (+ _present.tex)
#   output/reg/h2_snsv_d12_k2updn.tex (+ _present.tex)
#   output/reg/h3_inf_formal_d12_k2updn.tex (+ _present.tex)
# Author: EK  Date: 2026-09-23
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

# ── 1. Panel ─────────────────────────────────────────────────────────────
main_dat <- build_k2_panel("main")

# Lone-state screen, verbatim from run_k2_main_tables.r:30-44.
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

# Downstream mines and sulfur: the k=2 downstream-direction (placebo-arm)
# rows of step_instruments.parquet. Built by the same build_k_table() as the
# upstream columns, so `sulfur_mean0` is the zero-imputed mean in both
# directions (watersheds with no borehole match enter as 0).
si_dn <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet")) %>%
  dplyr::filter(arm == "placebo", k == 2) %>%
  dplyr::select(PWSID, year,
                num_coal_mines_down_sum = num_coal_mines_linked_sum,
                sulfur_down_mean0       = sulfur_mean0,
                sulfur_down_meancov     = sulfur_meancov,
                cov_share_down          = cov_share,
                n_hucs_linked_down      = n_hucs_linked,
                n_hucs_covered_down     = n_hucs_covered)
stopifnot(is.character(si_dn$PWSID),
          !any(duplicated(si_dn[, c("PWSID", "year")])))

n_util_pre <- dplyr::n_distinct(main_dat$PWSID); n_obs_pre <- nrow(main_dat)
main_dat <- main_dat %>% dplyr::left_join(si_dn, by = c("PWSID", "year"))
stopifnot(
  is.character(main_dat$PWSID),
  nrow(main_dat) == n_obs_pre,
  dplyr::n_distinct(main_dat$PWSID) == n_util_pre,
  !anyNA(main_dat$num_coal_mines_down_sum),
  !anyNA(main_dat$sulfur_down_mean0),
  !anyNA(main_dat$cov_share_down)
)
cat(sprintf("Downstream join: %d rows, %d utilities, no missing downstream values.\n",
            nrow(main_dat), dplyr::n_distinct(main_dat$PWSID)))

# Mirror gate: zero-imputation rule holds identically in both directions.
mirror_ok <- function(mean0, meancov, cov) all(abs(mean0 - dplyr::coalesce(meancov, 0) * cov) < 1e-8)
stopifnot(mirror_ok(main_dat$sulfur_mean0, main_dat$sulfur_meancov, main_dat$cov_share),
          mirror_ok(main_dat$sulfur_down_mean0, main_dat$sulfur_down_meancov, main_dat$cov_share_down))
cat("Sulfur mirror gate PASSED (sulfur_mean0 == coalesce(meancov, 0) * cov_share, both directions).\n")

util_cov <- main_dat %>% dplyr::group_by(PWSID) %>% dplyr::summarise(
  up_n = dplyr::first(n_hucs_linked), up_cov = dplyr::first(cov_share),
  up_zero = dplyr::first(n_hucs_covered) == 0,
  dn_n = dplyr::first(n_hucs_linked_down), dn_cov = dplyr::first(cov_share_down),
  dn_zero = dplyr::first(n_hucs_covered_down) == 0,
  dn_mine_ever = any(num_coal_mines_down_sum > 0),
  dn_sulfur_pos = any(sulfur_down_mean0 > 0), .groups = "drop")
cat(sprintf("Coverage (%d utilities): upstream %.1f linked HUCs, %.0f%% coverage, %d with zero covered HUCs\n",
            nrow(util_cov), mean(util_cov$up_n), 100 * mean(util_cov$up_cov), sum(util_cov$up_zero)))
cat(sprintf("Coverage (%d utilities): downstream %.1f linked HUCs, %.0f%% coverage, %d with zero covered HUCs\n",
            nrow(util_cov), mean(util_cov$dn_n), 100 * mean(util_cov$dn_cov), sum(util_cov$dn_zero)))
cat(sprintf("Utilities ever with a downstream mine-year > 0: %d; with downstream sulfur > 0: %d\n",
            sum(util_cov$dn_mine_ever), sum(util_cov$dn_sulfur_pos)))

# Explicit instrument columns so formulas and coefficient lookups are simple.
main_dat$z_up <- main_dat$post95 * main_dat$sulfur_mean0
main_dat$z_dn <- main_dat$post95 * main_dat$sulfur_down_mean0
cat(sprintf("corr(upstream sulfur, downstream sulfur) = %.2f; corr(z_up, z_dn) = %.2f\n",
            cor(main_dat$sulfur_mean0, main_dat$sulfur_down_mean0), cor(main_dat$z_up, main_dat$z_dn)))

FE_TWO      <- c("PWSID + year", "PWSID + STATE_CODE^year")
fe_state_yr <- "PWSID + STATE_CODE^year"
UP <- "num_coal_mines_linked_sum"
DN <- "num_coal_mines_down_sum"

# ── 2. Sample-identity anchor ────────────────────────────────────────────
# Single-instrument MR 2SLS on the joined panel must reproduce the existing
# _k2 MR table (state x year FE), proving the sample is unchanged.
single_iv <- function(dat, oc, fe) {
  dat_y <- dat[!is.na(dat[[oc]]), ]
  fixest::feols(as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", UP, " ~ post95:sulfur_mean0")),
                data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
}
anchor_want <- list(nitrates_MR_bin = c(3.94, 1.75), arsenic_MR_bin = c(3.78, 1.55),
                    inorganic_chemicals_MR_bin = c(3.06, 1.66))
anchor_n <- NULL
for (oc in names(anchor_want)) {
  m <- single_iv(main_dat, oc, fe_state_yr)
  t <- get_term(m, UP)
  cat(sprintf("Anchor (single instrument, state x year FE): %s %.2f (%.2f) [want %.2f (%.2f)]\n",
              oc, t$est, t$se, anchor_want[[oc]][1], anchor_want[[oc]][2]))
  stopifnot(abs(round(t$est, 2) - anchor_want[[oc]][1]) < 0.01,
            abs(round(t$se, 2)  - anchor_want[[oc]][2]) < 0.01)
  anchor_n <- rbind(anchor_n, c(n_obs = nobs(m), n_utils = length(fixest::fixef(m)$PWSID)))
}
stopifnot(all(anchor_n[, "n_obs"] == 10641), all(anchor_n[, "n_utils"] == 565))
cat("Sample-identity anchor gate PASSED (565 utilities / 10,641 obs).\n")

# ── 3. Helpers ───────────────────────────────────────────────────────────
k2_dict_updn <- c(k2_dict,
  num_coal_mines_down_sum   = "Downstream coal mines (sum)",
  num_coal_mines_linked_sum = "Upstream coal mines (sum)",
  z_up                      = "Post-1995 $\\times$ Upstream sulfur \\%",
  z_dn                      = "Post-1995 $\\times$ Downstream sulfur \\%"
)
k2_dict_updn <- k2_dict_updn[!duplicated(names(k2_dict_updn), fromLast = TRUE)]

# Clustered first-stage F for each endogenous variable: clustered Wald F of
# (z_up, z_dn) in that variable's first stage (never fixest's ivf1 -- HC1).
fs_stats_updn <- function(dat, fe) {
  endo <- c(up = UP, dn = DN)
  out <- list()
  for (nm in names(endo)) {
    fs <- fixest::feols(as.formula(paste0(endo[[nm]], " ~ z_up + z_dn + num_facilities | ", fe)),
                        data = dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    joint_f <- unname(fixest::wald(fs, keep = "^z_(up|dn)$", print = FALSE)$stat)
    out[[nm]] <- list(fs = fs, joint_f = joint_f)
  }
  out
}

# Decimal-alignment width computed over every term in a column.
fmt_col_multi <- function(terms_list, digits = 2) {
  int_w <- function(x) {
    if (is.na(x)) return(0L)
    nchar(sub("\\..*$", "", sprintf(paste0("%.", digits, "f"), abs(x))))
  }
  w <- max(sapply(terms_list, function(t) max(int_w(t$est), int_w(t$se))))
  lapply(terms_list, function(t) fmt_num_wide(t$est, t$se, t$pval, w, digits))
}

range_str <- function(v) {
  u <- unique(round(v, 2))
  if (length(u) == 1) fmt_single(u) else paste0(fmt_single(min(v)), " to ", fmt_single(max(v)))
}

# Copy of render_panel_k2 (k2_common.r:250-438) with two endogenous
# variables and two instruments: each OLS / 2SLS / RF panel has two
# coefficient + SE row pairs.
render_panel_k2_updn <- function(dat, outcomes, fe_specs, dict,
                                  title, label, outfile,
                                  depvar_sentence, extra_note = NULL, superheader = NULL,
                                  notes_present = NULL) {
  n_oc  <- length(outcomes)
  n_fe  <- length(fe_specs)
  n_col <- n_oc * n_fe

  oc_labels <- unname(sapply(names(outcomes), function(v) if (v %in% names(dict)) dict[[v]] else v))
  up_lab <- dict[[UP]]; dn_lab <- dict[[DN]]
  zu_lab <- dict[["z_up"]]; zd_lab <- dict[["z_dn"]]

  col_oc <- rep(names(outcomes), each = n_fe)
  col_fe <- rep(fe_specs, times = n_oc)

  ols_list <- vector("list", n_col); rf_list <- vector("list", n_col); iv_list <- vector("list", n_col)
  jf_up <- numeric(n_col); jf_dn <- numeric(n_col)
  n_utils <- integer(n_col); n_obs <- integer(n_col)

  for (j in seq_len(n_col)) {
    oc <- col_oc[j]; fe <- col_fe[j]
    dat_y <- dat[!is.na(dat[[oc]]), ]
    f_ols <- as.formula(paste0(oc, " ~ ", UP, " + ", DN, " + num_facilities | ", fe))
    f_rf  <- as.formula(paste0(oc, " ~ z_up + z_dn + num_facilities | ", fe))
    f_iv  <- as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", UP, " + ", DN, " ~ z_up + z_dn"))
    ols_list[[j]] <- fixest::feols(f_ols, data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    rf_list[[j]]  <- fixest::feols(f_rf,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    iv_list[[j]]  <- fixest::feols(f_iv,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    fsj <- fs_stats_updn(dat_y, fe)
    jf_up[j] <- fsj$up$joint_f; jf_dn[j] <- fsj$dn$joint_f
    n_utils[j] <- length(fixest::fixef(iv_list[[j]])$PWSID)
    n_obs[j]   <- nobs(iv_list[[j]])
  }

  col_fmts <- lapply(seq_len(n_col), function(j) fmt_col_multi(list(
    get_term(ols_list[[j]], UP), get_term(ols_list[[j]], DN),
    get_term(iv_list[[j]],  UP), get_term(iv_list[[j]],  DN),
    get_term(rf_list[[j]], "z_up"), get_term(rf_list[[j]], "z_dn"))))
  cells_k <- function(k) lapply(col_fmts, `[[`, k)

  # Wider than render_panel_k2: long row labels (e.g. "Post-1995 x Downstream
  # sulfur %") must fit on one line, and downstream 2SLS coefs/SEs reach two
  # integer digits. adjustbox scales the whole tabular to \linewidth.
  label_w_cm <- 7
  max_w_cm   <- 19
  data_w_cm  <- min(3, (max_w_cm - label_w_cm) / n_col)
  label_w    <- paste0(label_w_cm, "cm")
  data_w     <- paste0(data_w_cm, "cm")
  col_spec   <- paste0(">{\\raggedright\\arraybackslash}p{", label_w, "}",
                        paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w, "}"), n_col), collapse = ""))
  centered_data_col <- paste0(">{\\centering\\arraybackslash}p{", data_w, "}")

  superheader_lines <- if (!is.null(superheader)) {
    paste0(" & \\multicolumn{", n_col, "}{c}{", superheader, "} \\\\")
  } else NULL

  colnum_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{(", seq_len(n_col), ")}")
  colnum_row   <- paste0(" & ", paste(colnum_cells, collapse = " & "), " \\\\")
  if (n_fe > 1) {
    grp_header_cells <- paste0("\\multicolumn{", n_fe, "}{c}{", oc_labels, "}")
    header_block <- c(paste0(" & ", paste(grp_header_cells, collapse = " & "), " \\\\"), colnum_row)
  } else {
    header_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{", oc_labels, "}")
    header_block <- c(paste0(" & ", paste(header_cells, collapse = " & "), " \\\\"), colnum_row)
  }

  title_row <- function(model_label) paste0("\\multicolumn{", n_col + 1, "}{l}{", model_label, "} \\\\")
  coef_line <- function(cells, row_label) paste0(row_label, " & ", paste(sapply(cells, `[[`, "coef"), collapse = " & "), " \\\\")
  se_line   <- function(cells) paste0(" & ", paste(sapply(cells, `[[`, "se"), collapse = " & "), " \\\\")
  pair      <- function(k, row_label) c(coef_line(cells_k(k), row_label), se_line(cells_k(k)))

  fe_state     <- vapply(col_fe, function(fe) grepl("STATE_CODE^year", fe, fixed = TRUE), logical(1))
  fe_year      <- vapply(col_fe, function(fe) "year" %in% trimws(strsplit(fe, "\\+")[[1]]), logical(1))
  chk_all      <- paste(rep("$\\checkmark$", n_col), collapse = " & ")
  chk_state    <- paste(ifelse(fe_state, "$\\checkmark$", ""), collapse = " & ")
  chk_year     <- paste(ifelse(fe_year, "$\\checkmark$", ""), collapse = " & ")
  fe_row_util  <- paste0("Utility fixed effects & ", chk_all, " \\\\")
  fe_row_year  <- paste0("Year fixed effects & ", chk_year, " \\\\")
  fe_row_state <- paste0("State $\\times$ year fixed effects & ", chk_state, " \\\\")
  n_util_row   <- paste0("Utilities & ", paste(format(n_utils, big.mark = ","), collapse = " & "), " \\\\")
  n_obs_row    <- paste0("Observations & ", paste(format(n_obs, big.mark = ","), collapse = " & "), " \\\\")

  tabcolsep_pt    <- 4
  cm_per_pt       <- 2.54 / 72.27
  textwidth_cm    <- 16.51
  intercol_pad_cm <- 2 * (n_col + 1) * tabcolsep_pt * cm_per_pt
  natural_w_cm    <- label_w_cm + n_col * data_w_cm + intercol_pad_cm
  needs_scale     <- natural_w_cm > textwidth_cm
  total_w         <- if (needs_scale) "\\linewidth" else paste0(round(natural_w_cm, 4), "cm")

  wrap_panel <- function(lines) {
    if (!needs_scale) return(lines)
    tab_start <- grep("^\\\\begin\\{tabular\\}", lines)[1]
    tab_end   <- max(grep("^\\\\end\\{tabular\\}", lines))
    c(lines[seq_len(tab_start - 1)],
      "\\begin{adjustbox}{max width=\\linewidth}",
      lines[tab_start:tab_end],
      "\\end{adjustbox}",
      if (tab_end < length(lines)) lines[(tab_end + 1):length(lines)] else NULL)
  }

  panel_ols <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\toprule",
    superheader_lines,
    header_block,
    "\\hline",
    title_row("OLS"),
    pair(1, up_lab), pair(2, dn_lab),
    "\\end{tabular}"
  ))
  panel_iv <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline",
    title_row("2SLS"),
    pair(3, up_lab), pair(4, dn_lab),
    "\\end{tabular}"
  ))
  panel_rf <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline",
    title_row("RF"),
    pair(5, zu_lab), pair(6, zd_lab),
    "\\hline",
    fe_row_util, fe_row_year, fe_row_state,
    n_util_row, n_obs_row,
    "\\bottomrule",
    "\\end{tabular}"
  ))

  f_note <- paste0(
    "Upstream and downstream coal mines are instrumented jointly using both instruments. ",
    "The first-stage F-statistic (clustered at the utility level) for both instruments ",
    if (n_col > 1 && (length(unique(round(jf_up, 2))) > 1 || length(unique(round(jf_dn, 2))) > 1))
      "ranges across columns from " else "is ",
    range_str(jf_up), " for upstream coal mines and ", range_str(jf_dn), " for downstream coal mines."
  )
  note_text <- notes_k2(depvar_sentence, f_note = f_note, extra = extra_note)

  build_table_lines <- function(note_text_val) c(
    "\\begin{table}[htbp]",
    "\\raggedright",
    paste0("\\begin{minipage}{", total_w, "}"),
    paste0("\\caption{\\label{", label, "} ", title, "}"),
    "\\end{minipage}",
    "\\small",
    "{\\setlength{\\tabcolsep}{4pt}%",
    panel_ols,
    panel_iv,
    panel_rf,
    "}",
    paste0("\\begin{minipage}{", total_w, "}"),
    "\\vspace{4pt}",
    "\\footnotesize",
    "\\raggedright",
    note_text_val,
    "\\end{minipage}",
    "\\end{table}"
  )

  out_path <- file.path(ROOT, "output/reg", paste0(outfile, ".tex"))
  writeLines(build_table_lines(note_text), out_path)
  cat("  k2updn panel table written to:", out_path, "\n")
  if (!is.null(notes_present)) {
    out_path_present <- file.path(ROOT, "output/reg", paste0(outfile, "_present.tex"))
    writeLines(build_table_lines(notes_present), out_path_present)
    cat("  k2updn panel presentation table written to:", out_path_present, "\n")
  }

  invisible(list(jf_up = jf_up, jf_dn = jf_dn,
                 n_utils = n_utils, n_obs = n_obs, col_oc = col_oc, col_fe = col_fe,
                 iv_list = iv_list, rf_list = rf_list, ols_list = ols_list))
}

# ── 4. Tables ────────────────────────────────────────────────────────────
instr_clause <- paste0(
  "The two instruments interact an indicator for the post-1995 period with the average ",
  "coal sulfur content of watersheds within two flow steps upstream and, separately, ",
  "within two flow steps downstream of the utility's intake. Downstream coal mines are ",
  "the number of coal mines in watersheds within two flow steps downstream of the ",
  "utility's intake, summed across those watersheds."
)
sample_clause <- paste0(
  "The sample is utilities with a coal mine within two flow steps upstream of their ",
  "intake and no coal mine colocated with their intake, in states with at least one ",
  "other such utility."
)
depvar_vio <- paste0(
  "Dependent variable equals 1 if the utility had a violation of that type during the ",
  "year, 0 otherwise; coefficients and standard errors are multiplied by 100 to show ",
  "percentage point change. ", instr_clause, " ", sample_clause
)
notes_present_panel <- "\\textit{Notes:} Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
title_vio <- "Effect of upstream and downstream coal mines on inorganic chemical violations at utilities"

# 4.1 Any-category violations
r41 <- render_panel_k2_updn(
  dat        = main_dat,
  outcomes   = c(nitrates_bin = "Nitrates", arsenic_bin = "Arsenic",
                 inorganic_chemicals_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict_updn,
  title      = title_vio,
  label      = "tab:2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2updn",
  outfile    = "2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2updn",
  depvar_sentence = depvar_vio,
  superheader = "Any violation",
  notes_present = notes_present_panel
)

# 4.2 MR violations
r42 <- render_panel_k2_updn(
  dat        = main_dat,
  outcomes   = c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic",
                 inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict_updn,
  title      = title_vio,
  label      = "tab:2sls_dwnstrm_minevio_mr_ivsum_binvio_k2updn",
  outfile    = "2sls_dwnstrm_minevio_mr_ivsum_binvio_k2updn",
  depvar_sentence = depvar_vio,
  superheader = "Monitoring and reporting (MR) violation",
  notes_present = notes_present_panel
)

# 4.3 MCL violations
r43 <- render_panel_k2_updn(
  dat        = main_dat,
  outcomes   = c(nitrates_MCL_bin = "Nitrates", arsenic_MCL_bin = "Arsenic",
                 inorganic_chemicals_MCL_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict_updn,
  title      = title_vio,
  label      = "tab:2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2updn",
  outfile    = "2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2updn",
  depvar_sentence = depvar_vio,
  superheader = "Maximum contaminant level (MCL) violation",
  notes_present = notes_present_panel
)

# 4.4 First stage (state x year FE, as in the single-instrument table)
fs_all <- fs_stats_updn(main_dat, fe_state_yr)
cat(sprintf("\nFirst stage (state x year FE): joint F up %.2f / down %.2f [probe 24.68 / 18.31]\n",
            fs_all$up$joint_f, fs_all$dn$joint_f))

el_fs <- list(
  "F-test (1st stage, clustered)"      = c(fmt_single(fs_all$up$joint_f), fmt_single(fs_all$dn$joint_f)),
  "Utility fixed effects"              = c("$\\checkmark$", "$\\checkmark$"),
  "State $\\times$ year fixed effects" = c("$\\checkmark$", "$\\checkmark$")
)
fs_notes <- notes_k2(paste0(
  "The dependent variable is the number of coal mines in watersheds within two flow ",
  "steps upstream (column 1) or downstream (column 2) of the utility's intake, summed ",
  "across those watersheds. ", instr_clause, " ", sample_clause
))
fs_title <- "First stage: effect of the Acid Rain Program on the number of upstream and downstream coal mines (summed across watersheds within two flow steps)"
for (v in c("full", "present")) {
  etable(
    fs_all$up$fs, fs_all$dn$fs,
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    digits          = "r4",
    drop            = "Number of intake facilities",
    drop.section    = "fixef",
    title           = fs_title,
    label           = "tab:fs_dwnstrm_minevio_ivsum_k2updn",
    extralines      = el_fs,
    fitstat         = ~ n,
    dict            = k2_dict_updn,
    notes           = if (v == "full") fs_notes else notes_present_panel,
    # \par before the notes group closes, so its \raggedright applies instead
    # of the float's \centering (notes must be left-justified).
    postprocess.tex = function(x) sub("p$<$0.1.}", "p$<$0.1.\\par}",
                                      right_align_tabular(move_notes_below_adjustbox(x)), fixed = TRUE),
    file            = file.path(ROOT, "output/reg",
                                paste0("fs_dwnstrm_minevio_ivsum_k2updn", if (v == "present") "_present" else "", ".tex")),
    replace         = TRUE
  )
}
cat("  Written: output/reg/fs_dwnstrm_minevio_ivsum_k2updn.tex (+ _present)\n")

# 4.5 Exclusion-restriction falsification test
m1 <- fixest::feols(num_facilities ~ z_up + z_dn | PWSID + STATE_CODE^year,
                     data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)
n_years_expected <- length(unique(main_dat$year))
year_counts <- main_dat %>% dplyr::group_by(PWSID) %>%
  dplyr::summarise(n_years = dplyr::n_distinct(year), .groups = "drop")
balanced_ids <- year_counts$PWSID[year_counts$n_years == n_years_expected]
dat_bal <- main_dat[main_dat$PWSID %in% balanced_ids, ]
cat(sprintf("Balanced-panel subsample: %d utilities (of %d), %d obs\n",
            length(balanced_ids), dplyr::n_distinct(main_dat$PWSID), nrow(dat_bal)))
m2 <- fixest::feols(num_facilities ~ sulfur_mean0 + sulfur_down_mean0 + z_up + z_dn | year,
                     data = dat_bal, cluster = ~PWSID, warn = FALSE, notes = FALSE)

DIGITS_ET <- 4
col1_fmt <- fmt_col_multi(list(get_term(m1, "z_up"), get_term(m1, "z_dn")), DIGITS_ET)
col2_fmt <- fmt_col_multi(list(get_term(m2, "sulfur_mean0"), get_term(m2, "sulfur_down_mean0"),
                               get_term(m2, "z_up"), get_term(m2, "z_dn")), DIGITS_ET)
et_rows <- c(
  paste0("Upstream sulfur & & ", col2_fmt[[1]]$coef, " \\\\"),
  paste0(" & & ", col2_fmt[[1]]$se, " \\\\"),
  paste0("Downstream sulfur & & ", col2_fmt[[2]]$coef, " \\\\"),
  paste0(" & & ", col2_fmt[[2]]$se, " \\\\"),
  paste0("Post-1995 $\\times$ Upstream sulfur & ", col1_fmt[[1]]$coef, " & ", col2_fmt[[3]]$coef, " \\\\"),
  paste0(" & ", col1_fmt[[1]]$se, " & ", col2_fmt[[3]]$se, " \\\\"),
  paste0("Post-1995 $\\times$ Downstream sulfur & ", col1_fmt[[2]]$coef, " & ", col2_fmt[[4]]$coef, " \\\\"),
  paste0(" & ", col1_fmt[[2]]$se, " & ", col2_fmt[[4]]$se, " \\\\")
)

n_y_et <- 2
label_w_cm_et <- 5.5
data_w_cm_et  <- 2.5
# Plain "r" data columns so centered headers sit above the numbers
# (see run_k2_main_tables.r:257-263).
col_spec_et <- paste0("p{", label_w_cm_et, "cm}", paste(rep("r", n_y_et), collapse = ""))
tabcolsep_pt <- 4
cm_per_pt    <- 2.54 / 72.27
textwidth_cm <- 16.51
natural_w_cm_et <- label_w_cm_et + n_y_et * data_w_cm_et + 2 * (n_y_et + 1) * tabcolsep_pt * cm_per_pt
needs_scale_et  <- natural_w_cm_et > textwidth_cm
total_w_et <- if (needs_scale_et) "\\linewidth" else paste0(round(natural_w_cm_et, 4), "cm")

tabular_lines_et <- c(
  paste0("\\begin{tabular}{", col_spec_et, "}"),
  "\\toprule",
  " & \\multicolumn{2}{c}{Number of Intake Facilities} \\\\",
  " & \\multicolumn{1}{c}{(1)} & \\multicolumn{1}{c}{(2)} \\\\",
  "\\hline",
  et_rows,
  "\\hline",
  "Utility fixed effects & $\\checkmark$ & \\\\",
  "Year fixed effects & & $\\checkmark$ \\\\",
  "State $\\times$ year fixed effects & $\\checkmark$ & \\\\",
  "Balanced panel & & $\\checkmark$ \\\\",
  paste0("Utilities & ", format(length(fixest::fixef(m1)$PWSID), big.mark = ","), " & ",
         format(length(balanced_ids), big.mark = ","), " \\\\"),
  paste0("Observations & ", format(nobs(m1), big.mark = ","), " & ", format(nobs(m2), big.mark = ","), " \\\\"),
  "\\bottomrule",
  "\\end{tabular}"
)
if (needs_scale_et) {
  tabular_lines_et <- c("\\begin{adjustbox}{max width=\\linewidth}", tabular_lines_et, "\\end{adjustbox}")
}
note_et <- notes_k2(paste0(
  "The dependent variable is the number of active intake facilities operated by the ",
  "utility in that year. Upstream and downstream sulfur are the average coal sulfur ",
  "content of watersheds within two flow steps upstream and downstream of the utility's ",
  "intake. ", sample_clause
))
et_table <- function(note_val) c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  paste0("\\begin{minipage}{", total_w_et, "}"),
  "\\caption{\\label{tab:exclusion_test_num_facilities_k2updn} Effect of upstream and downstream instruments on utility characteristics}",
  "\\end{minipage}",
  "\\small",
  "{\\setlength{\\tabcolsep}{4pt}%",
  tabular_lines_et,
  "}",
  paste0("\\begin{minipage}{", total_w_et, "}"),
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  note_val,
  "\\end{minipage}",
  "\\end{table}"
)
writeLines(et_table(note_et), file.path(ROOT, "output/reg/exclusion_test_num_facilities_k2updn.tex"))
writeLines(et_table(notes_present_panel), file.path(ROOT, "output/reg/exclusion_test_num_facilities_k2updn_present.tex"))
cat("  Written: output/reg/exclusion_test_num_facilities_k2updn.tex (+ _present)\n")

# 4.6 Visit types (state x year FE only, as in the existing table)
depvar_visit <- paste0(
  "Dependent variable equals 1 if the utility received a regulator visit of that type ",
  "during the year, 0 otherwise; coefficients and standard errors are multiplied by 100 ",
  "to show percentage point change. ", instr_clause, " ", sample_clause
)
r46 <- render_panel_k2_updn(
  dat        = main_dat,
  outcomes   = c(any_snsv = "Sanitary", any_tech = "Technical assistance",
                 any_enfvisit = "Enforcement", any_smpl = "Sample collection",
                 any_insp = "Inspection"),
  fe_specs   = fe_state_yr,
  dict       = k2_dict_updn,
  title      = "Effect of upstream and downstream coal mining on regulator visit probability by visit type",
  label      = "tab:h2_snsv_d12_k2updn",
  outfile    = "h2_snsv_d12_k2updn",
  depvar_sentence = depvar_visit,
  notes_present = notes_present_panel
)

# 4.7 Enforcement types
depvar_enf <- paste0(
  "Dependent variable equals 1 if the utility had an enforcement action of that type ",
  "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise; ",
  "coefficients and standard errors are multiplied by 100 to show percentage point ",
  "change. ", instr_clause, " ", sample_clause
)
r47 <- render_panel_k2_updn(
  dat        = main_dat,
  outcomes   = c(any_informal = "Informal", any_formal = "Formal", no_enf = "None"),
  fe_specs   = FE_TWO,
  dict       = k2_dict_updn,
  title      = "Effect of upstream and downstream coal mining on enforcement actions by type",
  label      = "tab:h3_inf_formal_d12_k2updn",
  outfile    = "h3_inf_formal_d12_k2updn",
  depvar_sentence = depvar_enf,
  superheader = "Enforcement",
  notes_present = notes_present_panel
)

# ── 5. Gates and exclusion-test summary ─────────────────────────────────
for (nm in c("r42", "r47")) {
  r <- get(nm)
  stopifnot(length(unique(r$n_obs)) == 1, length(unique(r$n_utils)) == 1,
            r$n_obs[1] == 10641, r$n_utils[1] == 565)
  cat(sprintf("%s stable-sample gate PASSED: %s utilities / %s obs in every column.\n",
              nm, format(r$n_utils[1], big.mark = ","), format(r$n_obs[1], big.mark = ",")))
}

exog_summary <- function(r, table_name) {
  do.call(rbind, lapply(seq_along(r$iv_list), function(j) {
    iv <- r$iv_list[[j]]
    ci <- confint(iv, parm = paste0("fit_", DN), level = 0.95)
    dn <- get_term(iv, DN); up <- get_term(iv, UP)
    up1 <- get_term(single_iv(main_dat, r$col_oc[j], r$col_fe[j]), UP)
    data.frame(table = table_name, outcome = r$col_oc[j],
               fe = ifelse(grepl("STATE_CODE", r$col_fe[j]), "state x yr", "util + yr"),
               dn_est = round(dn$est, 2), dn_se = round(dn$se, 2),
               dn_ci_lo = round(ci[1, 1], 2), dn_ci_hi = round(ci[1, 2], 2),
               dn_p = round(dn$pval, 3), dn_zero = dn$pval >= 0.1,
               up_est = round(up$est, 2), up_se = round(up$se, 2), up_p = round(up$pval, 3),
               up_single = round(up1$est, 2), up_single_se = round(up1$se, 2),
               f_up = round(r$jf_up[j], 2), f_dn = round(r$jf_dn[j], 2))
  }))
}
exog <- rbind(exog_summary(r41, "any"), exog_summary(r42, "MR"), exog_summary(r43, "MCL"),
              exog_summary(r46, "visit"), exog_summary(r47, "enf"))
options(width = 250)
cat("\n=== Exclusion test: downstream 2SLS coefficient (pass = not significant at 10%) ===\n")
print(exog, row.names = FALSE)
cat(sprintf("\nDownstream coefficient significant at 10%% in %d of %d columns.\n",
            sum(!exog$dn_zero), nrow(exog)))
cat(sprintf("First-stage F range: upstream %.2f-%.2f, downstream %.2f-%.2f (all > 10: %s)\n",
            min(exog$f_up), max(exog$f_up), min(exog$f_dn), max(exog$f_dn),
            all(c(exog$f_up, exog$f_dn) > 10)))

cat("\n=== run_k2_updn_tables.r DONE ===\n")
