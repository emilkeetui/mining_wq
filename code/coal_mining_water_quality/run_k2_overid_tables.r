# ============================================================
# Script: run_k2_overid_tables.r
# Purpose: Over-identified k=2 2SLS: ONE endogenous regressor (upstream coal
#          mines, summed over watersheds within two flow steps of the intake)
#          instrumented by TWO instruments, post95 x upstream sulfur and
#          post95 x downstream sulfur. Reports the joint clustered first-stage
#          F and a cluster-robust Hansen J overidentification test. Same
#          sample as the _k2 tables. Sources k2_common.r (unchanged); writes
#          only new `_k2overid`-suffixed files under output/reg/.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (directly + via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/step_purity_flags.parquet (via k2_common.r)
# Outputs (each + _present.tex):
#   output/reg/fs_dwnstrm_minevio_ivsum_k2overid.tex
#   output/reg/exclusion_test_num_facilities_k2overid.tex
#   output/reg/2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2overid.tex
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2overid.tex
#   output/reg/2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2overid.tex
#   output/reg/h2_snsv_d12_k2overid.tex
#   output/reg/h3_inf_formal_d12_k2overid.tex
# Author: EK  Date: 2026-10-21
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")
stopifnot(WQ_SAMPLE == "k2")

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

# Decimal-alignment width computed over every term in a column.
fmt_col_multi <- function(terms_list, digits = 2) {
  # tight cells: hanging sign / parentheses in a right-aligned column, so no
  # integer-width padding is needed
  lapply(terms_list, function(t) fmt_num_wide(t$est, t$se, t$pval, 1, digits, tight = TRUE))
}

range_str <- function(v) {
  u <- unique(round(v, 2))
  if (length(u) == 1) fmt_single(u) else paste0(fmt_single(min(v)), " to ", fmt_single(max(v)))
}

# Joint clustered Wald F of (z_up, z_dn) in the upstream-mines first stage
# (never fixest's ivf1 -- HC1).
fs_stats_overid <- function(dat, fe) {
  fs <- fixest::feols(as.formula(paste0(UP, " ~ z_up + z_dn + num_facilities | ", fe)),
                      data = dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)
  joint_f <- unname(fixest::wald(fs, keep = "^z_(up|dn)$", print = FALSE)$stat)
  list(fs = fs, joint_f = joint_f)
}

# Cluster-robust Hansen J: two-step efficient GMM on FE-demeaned data
# (as Stata ivreg2 ..., gmm2s cluster()). Step-1 2SLS must reproduce fixest.
hansen_j_cluster <- function(dat_y, oc, fe, iv_model) {
  vars <- c(oc, UP, "num_facilities", "z_up", "z_dn")
  dd <- dat_y[stats::complete.cases(dat_y[, c(vars, "PWSID", "year", "STATE_CODE")]), ]
  fe_df <- if (grepl("STATE_CODE^year", fe, fixed = TRUE))
    data.frame(PWSID = dd$PWSID, state_year = paste(dd$STATE_CODE, dd$year, sep = "_"))
  else data.frame(PWSID = dd$PWSID, year = dd$year)
  X_all <- as.matrix(dd[, vars])
  storage.mode(X_all) <- "double"
  dm <- fixest::demean(X_all, fe_df)
  y <- dm[, oc, drop = FALSE]
  X <- dm[, c(UP, "num_facilities"), drop = FALSE]
  Z <- dm[, c("z_up", "z_dn", "num_facilities"), drop = FALSE]
  Pz_X <- Z %*% solve(crossprod(Z), crossprod(Z, X))
  b1 <- solve(crossprod(Pz_X, X), crossprod(Pz_X, y))
  stopifnot(abs(b1[1] - coef(iv_model)[paste0("fit_", UP)]) < 1e-6)
  u1 <- y - X %*% b1
  g_c <- rowsum(Z * as.vector(u1), dd$PWSID)
  W <- solve(crossprod(g_c))
  ZX <- crossprod(Z, X); Zy <- crossprod(Z, y)
  b2 <- solve(t(ZX) %*% W %*% ZX, t(ZX) %*% W %*% Zy)
  u2 <- y - X %*% b2
  gbar <- crossprod(Z, u2)
  J <- as.numeric(t(gbar) %*% W %*% gbar)
  df <- ncol(Z) - ncol(X)
  list(J = J, df = df, p = pchisq(J, df, lower.tail = FALSE), b2 = b2[1])
}

render_panel_k2_overid <- function(dat, outcomes, fe_specs, dict,
                                    title, label, outfile,
                                    depvar_sentence, extra_note = NULL, superheader = NULL,
                                    notes_present = NULL) {
  n_oc  <- length(outcomes)
  n_fe  <- length(fe_specs)
  n_col <- n_oc * n_fe

  oc_labels <- unname(sapply(names(outcomes), function(v) if (v %in% names(dict)) dict[[v]] else v))
  up_lab <- dict[[UP]]; zu_lab <- dict[["z_up"]]; zd_lab <- dict[["z_dn"]]

  col_oc <- rep(names(outcomes), each = n_fe)
  col_fe <- rep(fe_specs, times = n_oc)

  ols_list <- vector("list", n_col); rf_list <- vector("list", n_col); iv_list <- vector("list", n_col)
  hj <- vector("list", n_col)
  jf <- numeric(n_col); n_utils <- integer(n_col); n_obs <- integer(n_col)

  for (j in seq_len(n_col)) {
    oc <- col_oc[j]; fe <- col_fe[j]
    dat_y <- dat[!is.na(dat[[oc]]), ]
    f_ols <- as.formula(paste0(oc, " ~ ", UP, " + num_facilities | ", fe))
    f_rf  <- as.formula(paste0(oc, " ~ z_up + z_dn + num_facilities | ", fe))
    f_iv  <- as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", UP, " ~ z_up + z_dn"))
    ols_list[[j]] <- fixest::feols(f_ols, data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    rf_list[[j]]  <- fixest::feols(f_rf,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    iv_list[[j]]  <- fixest::feols(f_iv,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    jf[j] <- fs_stats_overid(dat_y, fe)$joint_f
    hj[[j]] <- hansen_j_cluster(dat_y, oc, fe, iv_list[[j]])
    n_utils[j] <- length(fixest::fixef(iv_list[[j]])$PWSID)
    n_obs[j]   <- nobs(iv_list[[j]])
  }

  col_fmts <- lapply(seq_len(n_col), function(j) fmt_col_multi(list(
    get_term(ols_list[[j]], UP), get_term(iv_list[[j]], UP),
    get_term(rf_list[[j]], "z_up"), get_term(rf_list[[j]], "z_dn"))))
  cells_k <- function(k) lapply(col_fmts, `[[`, k)

  label_w_cm <- 7
  max_w_cm   <- 19
  data_w_cm  <- min(2, (max_w_cm - label_w_cm) / n_col)
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
    header_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{\\footnotesize ", oc_labels, "}")
    header_block <- c(paste0(" & ", paste(header_cells, collapse = " & "), " \\\\"), colnum_row)
  }

  title_row <- function(model_label) paste0("\\multicolumn{", n_col + 1, "}{l}{", model_label, "} \\\\")
  coef_line <- function(cells, row_label) paste0(row_label, " & ", paste(sapply(cells, `[[`, "coef"), collapse = " & "), " \\\\")
  se_line   <- function(cells) paste0(" & ", paste(sapply(cells, `[[`, "se"), collapse = " & "), " \\\\")
  pair      <- function(k, row_label) c(coef_line(cells_k(k), row_label), se_line(cells_k(k)))

  fe_state     <- vapply(col_fe, function(fe) grepl("STATE_CODE^year", fe, fixed = TRUE), logical(1))
  fe_year      <- vapply(col_fe, function(fe) "year" %in% trimws(strsplit(fe, "\\+")[[1]]), logical(1))
  fe_res <- fe_block(list("Utility" = rep(TRUE, n_col), "Year" = fe_year, "State $\\times$ year" = fe_state), data_w)
  nb     <- n_block(n_obs, n_utils)
  pad <- "\\phantom{$^{***}$}"
  f_rows <- c(
    paste0("First-stage F-statistic (joint) & ", paste0(fmt_fixed(jf, 2), pad, collapse = " & "), " \\\\"),
    paste0("Overidentification test p-value & ", paste0(fmt_p(vapply(hj, `[[`, numeric(1), "p")), pad, collapse = " & "), " \\\\")
  )

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
    "\\toprule", superheader_lines, header_block, "\\hline",
    title_row("OLS"), pair(1, up_lab),
    "\\end{tabular}"
  ))
  panel_iv <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline", title_row("2SLS"), pair(2, up_lab),
    "\\end{tabular}"
  ))
  panel_rf <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline", title_row("RF"),
    pair(3, zu_lab), pair(4, zd_lab),
    "\\hline",
    fe_res$rows, nb$rows, f_rows,
    "\\bottomrule",
    "\\end{tabular}"
  ))

  f_note <- paste0(
    "Upstream coal mines are instrumented with two instruments. The first-stage ",
    "F-statistic (clustered at the utility level) tests the two instruments jointly. ",
    "The overidentification test is Hansen's J statistic, robust to clustering at the ",
    "utility level, for the null hypothesis that both instruments are valid."
  )
  extra_note <- paste(c(extra_note, fe_res$note, nb$note), collapse = " ")
  note_text <- notes_k2(depvar_sentence, f_note = f_note, extra = extra_note)

  build_table_lines <- function(note_text_val) c(
    "\\begin{table}[htbp]",
    "\\centering",
    paste0("\\begin{minipage}{", total_w, "}"),
    paste0("\\caption{\\label{", label, "} ", title, "}"),
    "\\end{minipage}",
    "\\small",
    "{\\setlength{\\tabcolsep}{4pt}%",
    panel_ols, panel_iv, panel_rf,
    "}",
    paste0("\\begin{minipage}{", total_w, "}"),
    "\\vspace{4pt}", "\\footnotesize", "\\raggedright",
    note_text_val,
    "\\end{minipage}",
    "\\end{table}"
  )

  out_path <- file.path(ROOT, "output/reg", paste0(outfile, ".tex"))
  if (file.exists(out_path)) stop("Refusing to overwrite existing file: ", out_path)
  writeLines(build_table_lines(note_text), out_path)
  cat("  k2overid panel table written to:", out_path, "\n")
  if (!is.null(notes_present)) {
    out_path_present <- file.path(ROOT, "output/reg", paste0(outfile, "_present.tex"))
    writeLines(build_table_lines(notes_present), out_path_present)
  }

  invisible(list(jf = jf, hj = hj, n_utils = n_utils, n_obs = n_obs,
                 col_oc = col_oc, col_fe = col_fe,
                 iv_list = iv_list, rf_list = rf_list, ols_list = ols_list))
}

# ── 4. Tables ────────────────────────────────────────────────────────────
instr_clause <- paste0(
  "Upstream coal mines is the number of active coal mines in watersheds within two flow ",
  "steps upstream of the utility's intake, summed across those watersheds. The two ",
  "instruments interact an indicator for the post-1995 period with the average coal ",
  "sulfur content of watersheds within two flow steps upstream and, separately, within ",
  "two flow steps downstream of the utility's intake."
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
depvar_visit <- paste0(
  "Dependent variable equals 1 if the utility received a regulator visit of that type ",
  "during the year, 0 otherwise; coefficients and standard errors are multiplied by 100 ",
  "to show percentage point change. ", instr_clause, " ", sample_clause
)
depvar_enf <- paste0(
  "Dependent variable equals 1 if the utility had an enforcement action of that type ",
  "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise; ",
  "coefficients and standard errors are multiplied by 100 to show percentage point ",
  "change. ", instr_clause, " ", sample_clause
)
notes_present_panel <- "\\textit{Notes:} Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
title_vio <- "Effect of upstream coal mines on inorganic chemical violations at utilities, two instruments"

run_tab <- function(stem, outcomes, fe_specs, title, depvar, superheader = NULL) {
  render_panel_k2_overid(
    dat = main_dat, outcomes = outcomes, fe_specs = fe_specs, dict = k2_dict_updn,
    title = title, label = paste0("tab:", stem, "_k2overid"),
    outfile = paste0(stem, "_k2overid"), depvar_sentence = depvar,
    superheader = superheader, notes_present = notes_present_panel)
}

r41 <- run_tab("2sls_dwnstrm_minevio_allcat_ivsum_binvio",
  c(nitrates_bin = "Nitrates", arsenic_bin = "Arsenic", inorganic_chemicals_bin = "Inorganic chemicals"),
  FE_TWO, title_vio, depvar_vio, "Any violation")
r42 <- run_tab("2sls_dwnstrm_minevio_mr_ivsum_binvio",
  c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic", inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  FE_TWO, title_vio, depvar_vio, "Monitoring and reporting (MR) violation")
r43 <- run_tab("2sls_dwnstrm_minevio_mcl_ivsum_binvio",
  c(nitrates_MCL_bin = "Nitrates", arsenic_MCL_bin = "Arsenic", inorganic_chemicals_MCL_bin = "Inorganic chemicals"),
  FE_TWO, title_vio, depvar_vio, "Maximum contaminant level (MCL) violation")

# 4.4 First stage: z_up only, z_dn only, both (state x year FE)
fs1 <- fixest::feols(as.formula(paste0(UP, " ~ z_up + num_facilities | ", fe_state_yr)),
                     data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)
fs2 <- fixest::feols(as.formula(paste0(UP, " ~ z_dn + num_facilities | ", fe_state_yr)),
                     data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)
fs3 <- fs_stats_overid(main_dat, fe_state_yr)
f1 <- f_clustered(main_dat, fe_state_yr)
f2 <- unname((coef(fs2)["z_dn"] / fixest::se(fs2)["z_dn"])^2)
f3 <- fs3$joint_f
cat(sprintf("\nFirst stage F: z_up %.2f [want 49.20] / z_dn %.2f / joint %.2f [want 24.68]\n", f1, f2, f3))
stopifnot(abs(f1 - 49.20) < 0.01, abs(f3 - 24.68) < 0.01)
cat("First-stage F gates PASSED.\n")

fs_notes_fn <- function(extra) notes_k2(paste0(
  "The dependent variable is the number of coal mines in watersheds within two flow ",
  "steps upstream of the utility's intake, summed across those watersheds. ",
  "The two instruments interact an indicator for the post-1995 period with the average ",
  "coal sulfur content of watersheds within two flow steps upstream and, separately, ",
  "within two flow steps downstream of the utility's intake. ", sample_clause,
  " The first-stage F-statistic is clustered at the utility level; in column 3 it tests ",
  "both instruments jointly."
), extra = extra)
render_coef_table_k2(
  rows = list(
    list(label = k2_dict_updn[["z_up"]], terms = list(get_term(fs1, "z_up"), NULL, get_term(fs3$fs, "z_up"))),
    list(label = k2_dict_updn[["z_dn"]], terms = list(NULL, get_term(fs2, "z_dn"), get_term(fs3$fs, "z_dn")))
  ),
  col_headers = c("", "", ""), superheader = "Upstream coal mines (sum)",
  fe_list     = list("Utility" = rep(TRUE, 3), "State $\\times$ year" = rep(TRUE, 3)),
  f_rows      = list("First-stage F-statistic" = c(f1, f2, f3)),
  n_obs       = c(nobs(fs1), nobs(fs2), nobs(fs3$fs)),
  n_utils     = c(length(fixest::fixef(fs1)$PWSID), length(fixest::fixef(fs2)$PWSID), length(fixest::fixef(fs3$fs)$PWSID)),
  label       = "tab:fs_dwnstrm_minevio_ivsum_k2overid",
  title       = "First stage: effect of the instruments on the number of upstream coal mines, 1985--2005",
  outfile     = "fs_dwnstrm_minevio_ivsum_k2overid",
  note_text_fn = fs_notes_fn, notes_present = notes_present_panel,
  label_w_cm  = 6.5, data_w_cm = 2.5
)

# 4.5 Exclusion-restriction falsification (identical to the _k2updn version)
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

note_et_fn <- function(extra) notes_k2(paste0(
  "The dependent variable is the number of active intake facilities operated by the ",
  "utility in that year. Upstream and downstream sulfur are the average coal sulfur ",
  "content of watersheds within two flow steps upstream and downstream of the utility's ",
  "intake. ", sample_clause
), extra = extra)
render_coef_table_k2(
  rows = list(
    list(label = "Upstream sulfur \\%",   terms = list(NULL, get_term(m2, "sulfur_mean0"))),
    list(label = "Downstream sulfur \\%", terms = list(NULL, get_term(m2, "sulfur_down_mean0"))),
    list(label = k2_dict_updn[["z_up"]],  terms = list(get_term(m1, "z_up"), get_term(m2, "z_up"))),
    list(label = k2_dict_updn[["z_dn"]],  terms = list(get_term(m1, "z_dn"), get_term(m2, "z_dn")))
  ),
  col_headers = c("", ""), superheader = "Number of intake facilities",
  fe_list     = list("Utility" = c(TRUE, FALSE), "Year" = c(FALSE, TRUE), "State $\\times$ year" = c(TRUE, FALSE)),
  spec_rows   = list("Balanced panel" = c(FALSE, TRUE)),
  n_obs       = c(nobs(m1), nobs(m2)),
  n_utils     = c(length(fixest::fixef(m1)$PWSID), length(balanced_ids)),
  label       = "tab:exclusion_test_num_facilities_k2overid",
  title       = "Effect of instruments on utility characteristics",
  outfile     = "exclusion_test_num_facilities_k2overid",
  note_text_fn = note_et_fn, notes_present = notes_present_panel,
  label_w_cm  = 6.5
)

r46 <- run_tab("h2_snsv_d12",
  c(any_snsv = "Sanitary", any_tech = "Technical assistance", any_enfvisit = "Enforcement",
    any_smpl = "Sample collection", any_insp = "Inspection"),
  fe_state_yr, "Effect of upstream coal mining on regulator visit probability by visit type, two instruments",
  depvar_visit)
r47 <- run_tab("h3_inf_formal_d12",
  c(any_informal = "Informal", any_formal = "Formal", no_enf = "None"),
  FE_TWO, "Effect of upstream coal mining on enforcement actions by type, two instruments",
  depvar_enf, "Enforcement")

# ── 5. Gates and console summary ─────────────────────────────────────────
for (nm in c("r42", "r47")) {
  r <- get(nm)
  stopifnot(length(unique(r$n_obs)) == 1, length(unique(r$n_utils)) == 1,
            r$n_obs[1] == 10641, r$n_utils[1] == 565)
  cat(sprintf("%s stable-sample gate PASSED: %s utilities / %s obs in every column.\n",
              nm, format(r$n_utils[1], big.mark = ","), format(r$n_obs[1], big.mark = ",")))
}

summ <- function(r, table_name) {
  do.call(rbind, lapply(seq_along(r$iv_list), function(j) {
    iv <- r$iv_list[[j]]
    up <- get_term(iv, UP)
    up1 <- get_term(single_iv(main_dat, r$col_oc[j], r$col_fe[j]), UP)
    data.frame(table = table_name, outcome = r$col_oc[j],
               fe = ifelse(grepl("STATE_CODE", r$col_fe[j]), "state x yr", "util + yr"),
               ov_est = round(up$est, 2), ov_se = round(up$se, 2), ov_p = round(up$pval, 3),
               single_est = round(up1$est * 100, 2), single_se = round(up1$se * 100, 2),
               joint_f = round(r$jf[j], 2), J = round(r$hj[[j]]$J, 2), J_p = round(r$hj[[j]]$p, 3))
  }))
}
sm <- rbind(summ(r41, "any"), summ(r42, "MR"), summ(r43, "MCL"), summ(r46, "visit"), summ(r47, "enf"))
options(width = 250)
cat("\n=== Over-identified vs single-instrument 2SLS (upstream mines; pp) ===\n")
print(sm, row.names = FALSE)
cat(sprintf("\nColumns with Hansen J p < 0.10: %d of %d\n", sum(sm$J_p < 0.10), nrow(sm)))
cat(sprintf("Every joint first-stage F > 10: %s\n", all(sm$joint_f > 10)))
mr_chk <- sm[sm$table == "MR", ]
cat("MR over-identified estimates (single-instrument want 3.94 / 3.78 / 3.06 on state x yr):\n")
print(mr_chk[mr_chk$fe == "state x yr", c("outcome", "ov_est", "single_est")], row.names = FALSE)
if (any(mr_chk$ov_est[mr_chk$fe == "state x yr"] <= 0)) warning("SIGN FLIP in MR over-identified 2SLS -- report to user")

cat("\n=== run_k2_overid_tables.r DONE ===\n")
