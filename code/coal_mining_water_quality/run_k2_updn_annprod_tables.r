# ============================================================
# Script: run_k2_updn_annprod_tables.r
# Purpose: Regressor-swap version of the two-instrument k=2 2SLS tables
#          (run_k2_updn_tables.r): annual upstream AND downstream coal
#          production (1M short tons, each summed over watersheds within two
#          flow steps of the intake) instrumented jointly by post95 x upstream
#          sulfur and post95 x downstream sulfur, in place of the upstream and
#          downstream mine counts. Same sample, fixed effects, instruments and
#          layout. MR-violation, enforcement-type and visit-type tables only.
#          Sources k2_common.r; writes only new `_k2updnannprod`-suffixed files
#          under output/reg/.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (directly + via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/step_purity_flags.parquet (via k2_common.r)
# Outputs:
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2updnannprod.tex (+ _present.tex)
#   output/reg/h3_inf_formal_d12_k2updnannprod.tex (+ _present.tex)
#   output/reg/h2_snsv_d12_k2updnannprod.tex (+ _present.tex)
# Author: EK  Date: 2026-09-24
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

# ── 1. Panel ─────────────────────────────────────────────────────────────
main_dat <- build_k2_panel("main")

# Lone-state screen, verbatim from run_k2_updn_tables.r:36-46.
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

# Downstream sulfur and production: the k=2 downstream-direction (placebo-arm)
# rows of step_instruments.parquet, as in run_k2_updn_tables.r.
si_dn <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet")) %>%
  dplyr::filter(arm == "placebo", k == 2) %>%
  dplyr::select(PWSID, year,
                production_linked_sum_down = production_linked_sum,
                sulfur_down_mean0          = sulfur_mean0)
stopifnot(is.character(si_dn$PWSID),
          !any(duplicated(si_dn[, c("PWSID", "year")])))

n_util_pre <- dplyr::n_distinct(main_dat$PWSID); n_obs_pre <- nrow(main_dat)
main_dat <- main_dat %>% dplyr::left_join(si_dn, by = c("PWSID", "year"))
stopifnot(
  is.character(main_dat$PWSID),
  nrow(main_dat) == n_obs_pre,
  dplyr::n_distinct(main_dat$PWSID) == n_util_pre,
  !anyNA(main_dat$sulfur_down_mean0)
)

# Annual production in 1M short tons (NA -> 0, i.e. no linked output that
# year), same rule as run_k2_annprod_tables.r:49-50, applied in both directions.
main_dat$coal_prod_upstream_1mst   <- replace(main_dat$production_linked_sum,
                                              is.na(main_dat$production_linked_sum), 0) / 1e6
main_dat$coal_prod_downstream_1mst <- replace(main_dat$production_linked_sum_down,
                                              is.na(main_dat$production_linked_sum_down), 0) / 1e6
for (v in c("coal_prod_upstream_1mst", "coal_prod_downstream_1mst")) {
  cat(sprintf("%s: mean %.3f, max %.3f, share zero %.3f\n", v,
              mean(main_dat[[v]]), max(main_dat[[v]]), mean(main_dat[[v]] == 0)))
}
cat(sprintf("Utilities ever with downstream production > 0: %d of %d\n",
            dplyr::n_distinct(main_dat$PWSID[main_dat$coal_prod_downstream_1mst > 0]),
            dplyr::n_distinct(main_dat$PWSID)))

main_dat$z_up <- main_dat$post95 * main_dat$sulfur_mean0
main_dat$z_dn <- main_dat$post95 * main_dat$sulfur_down_mean0

FE_TWO      <- c("PWSID + year", "PWSID + STATE_CODE^year")
fe_state_yr <- "PWSID + STATE_CODE^year"
UP <- "coal_prod_upstream_1mst"
DN <- "coal_prod_downstream_1mst"

# ── 2. Sample-identity anchor ────────────────────────────────────────────
# Single-instrument production 2SLS on the joined panel must reproduce the
# existing _k2annprod MR table (state x year FE columns).
single_iv <- function(dat, oc, fe) {
  dat_y <- dat[!is.na(dat[[oc]]), ]
  fixest::feols(as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", UP, " ~ post95:sulfur_mean0")),
                data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
}
anchor_want <- list(nitrates_MR_bin = c(19.39, 9.87), arsenic_MR_bin = c(18.58, 9.10),
                    inorganic_chemicals_MR_bin = c(15.02, 8.99))
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
  coal_prod_upstream_1mst   = "Upstream coal prod. (1M ST)",
  coal_prod_downstream_1mst = "Downstream coal prod. (1M ST)",
  z_up                      = "Post-1995 $\\times$ Upstream sulfur \\%",
  z_dn                      = "Post-1995 $\\times$ Downstream sulfur \\%"
)
k2_dict_updn <- k2_dict_updn[!duplicated(names(k2_dict_updn), fromLast = TRUE)]

# fs_stats_updn(), fmt_col_multi(), range_str() and render_panel_k2_updn():
# copied from run_k2_updn_tables.r:140-344 (parameterized on the global UP/DN);
# only the endogenous-variable noun in the first-stage F note is changed.
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
    "Upstream and downstream coal production are instrumented jointly using both instruments. ",
    "The first-stage F-statistic (clustered at the utility level) for both instruments ",
    if (n_col > 1 && (length(unique(round(jf_up, 2))) > 1 || length(unique(round(jf_dn, 2))) > 1))
      "ranges across columns from " else "is ",
    range_str(jf_up), " for upstream coal production and ", range_str(jf_dn), " for downstream coal production."
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
  "within two flow steps downstream of the utility's intake. Upstream and downstream coal ",
  "production is coal production during the year, in millions of short tons, in watersheds ",
  "within two flow steps upstream and, separately, downstream of the utility's intake."
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

# 4.1 MR violations
r42 <- render_panel_k2_updn(
  dat        = main_dat,
  outcomes   = c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic",
                 inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  fe_specs   = FE_TWO,
  dict       = k2_dict_updn,
  title      = "Effect of upstream and downstream coal production on inorganic chemical violations at utilities",
  label      = "tab:2sls_dwnstrm_minevio_mr_ivsum_binvio_k2updnannprod",
  outfile    = "2sls_dwnstrm_minevio_mr_ivsum_binvio_k2updnannprod",
  depvar_sentence = depvar_vio,
  superheader = "Monitoring and reporting (MR) violation",
  notes_present = notes_present_panel
)

# 4.2 Visit types (state x year FE only, as in the mine-count table)
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
  title      = "Effect of upstream and downstream coal production on regulator visit probability by visit type",
  label      = "tab:h2_snsv_d12_k2updnannprod",
  outfile    = "h2_snsv_d12_k2updnannprod",
  depvar_sentence = depvar_visit,
  notes_present = notes_present_panel
)

# 4.3 Enforcement types
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
  title      = "Effect of upstream and downstream coal production on enforcement actions by type",
  label      = "tab:h3_inf_formal_d12_k2updnannprod",
  outfile    = "h3_inf_formal_d12_k2updnannprod",
  depvar_sentence = depvar_enf,
  superheader = "Enforcement",
  notes_present = notes_present_panel
)

# ── 5. Gates and exclusion-test summary ─────────────────────────────────
for (nm in c("r42", "r46", "r47")) {
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
exog <- rbind(exog_summary(r42, "MR"), exog_summary(r46, "visit"), exog_summary(r47, "enf"))
options(width = 250)
cat("\n=== Exclusion test: downstream 2SLS coefficient (pass = not significant at 10%) ===\n")
print(exog, row.names = FALSE)
cat(sprintf("\nDownstream coefficient significant at 10%% in %d of %d columns.\n",
            sum(!exog$dn_zero), nrow(exog)))
cat(sprintf("First-stage F range: upstream %.2f-%.2f, downstream %.2f-%.2f (all > 10: %s)\n",
            min(exog$f_up), max(exog$f_up), min(exog$f_dn), max(exog$f_dn),
            all(c(exog$f_up, exog$f_dn) > 10)))

cat("\n=== run_k2_updn_annprod_tables.r DONE ===\n")
