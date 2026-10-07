# ============================================================
# Script: run_k2_placement_tables.r
# Purpose: Placement-week slide versions of three k=2 main tables: utility
#          and observation counts moved from the table body to the notes,
#          and (visit / enforcement tables) 2SLS panel only.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
# Outputs:
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2_placement.tex
#   output/reg/h3_inf_formal_d12_k2_placement.tex
#   output/reg/h2_snsv_d12_k2_placement.tex
# Author: EK  Date: 2026-10-07
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

main_dat <- build_k2_panel("main")

# Same stable-sample screen as run_k2_main_tables.r: drop utilities with a
# missing state or that are the only utility in their state.
lone_states <- main_dat %>%
  dplyr::filter(!is.na(STATE_CODE)) %>%
  dplyr::group_by(STATE_CODE) %>%
  dplyr::summarise(n_util = dplyr::n_distinct(PWSID), .groups = "drop") %>%
  dplyr::filter(n_util == 1) %>%
  dplyr::pull(STATE_CODE)
main_dat <- main_dat %>% dplyr::filter(!is.na(STATE_CODE), !(STATE_CODE %in% lone_states))

FE_TWO      <- c("PWSID + year", "PWSID + STATE_CODE^year")
fe_state_yr <- "PWSID + STATE_CODE^year"
coalvar     <- "num_coal_mines_linked_sum"
instr_str   <- "post95:sulfur_mean0"

# ── Renderer ───────────────────────────────────────────────────────────────
# Mirrors render_panel_k2() layout. Differences: N rows go to the notes and
# `panels` selects which panels print.
render_placement_k2 <- function(dat, outcomes, fe_specs, outfile, title, label,
                                depvar_note, panels = c("ols", "iv", "rf"),
                                superheader = NULL) {
  n_oc <- length(outcomes); n_fe <- length(fe_specs); n_col <- n_oc * n_fe
  col_oc <- rep(names(outcomes), each = n_fe)
  col_fe <- rep(fe_specs, times = n_oc)

  ols_list <- rf_list <- iv_list <- vector("list", n_col)
  f_vals <- numeric(n_col); n_utils <- integer(n_col); n_obs <- integer(n_col)
  for (j in seq_len(n_col)) {
    oc <- col_oc[j]; fe <- col_fe[j]
    dat_y <- dat[!is.na(dat[[oc]]), ]
    ols_list[[j]] <- fixest::feols(as.formula(paste0(oc, " ~ ", coalvar, " + num_facilities | ", fe)),
                                   data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    rf_list[[j]]  <- fixest::feols(as.formula(paste0(oc, " ~ ", instr_str, " + num_facilities | ", fe)),
                                   data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    iv_list[[j]]  <- fixest::feols(as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", coalvar, " ~ ", instr_str)),
                                   data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    f_vals[j]     <- f_clustered(dat_y, fe, endog = coalvar)
    n_utils[j]    <- length(fixest::fixef(iv_list[[j]])$PWSID)
    n_obs[j]      <- nobs(iv_list[[j]])
  }
  stopifnot(length(unique(n_obs)) == 1, length(unique(n_utils)) == 1)

  ols_terms <- lapply(ols_list, function(m) get_term(m, coalvar))
  iv_terms  <- lapply(iv_list,  function(m) get_term(m, coalvar))
  rf_terms  <- lapply(rf_list,  function(m) get_term(m, instr_str))

  # Common integer width across printed panels only, for decimal alignment
  int_w <- function(x) if (is.na(x)) 0L else nchar(sub("\\..*$", "", sprintf("%.2f", abs(x))))
  terms_by_panel <- list(ols = ols_terms, iv = iv_terms, rf = rf_terms)[panels]
  cells <- lapply(names(terms_by_panel), function(p) {
    lapply(seq_len(n_col), function(j) {
      w <- max(unlist(lapply(terms_by_panel, function(tl) c(int_w(tl[[j]]$est), int_w(tl[[j]]$se)))))
      t <- terms_by_panel[[p]][[j]]
      fmt_num_wide(t$est, t$se, t$pval, w, 2)
    })
  })
  names(cells) <- names(terms_by_panel)

  coal_lab  <- k2_dict[[coalvar]]
  instr_lab <- paste(sapply(strsplit(instr_str, ":")[[1]], function(p) k2_dict[[p]]), collapse = " $\\times$ ")
  row_labs  <- c(ols = coal_lab, iv = coal_lab, rf = instr_lab)
  panel_titles <- c(ols = "OLS", iv = "2SLS", rf = "RF")

  label_w_cm <- 5.5
  data_w_cm  <- min(3, (16 - label_w_cm) / n_col)
  data_w     <- paste0(data_w_cm, "cm")
  col_spec   <- paste0("p{", label_w_cm, "cm}",
                       paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w, "}"), n_col), collapse = ""))
  centered   <- paste0(">{\\centering\\arraybackslash}p{", data_w, "}")
  oc_labels  <- unname(outcomes)

  header_block <- c(
    if (!is.null(superheader)) paste0(" & \\multicolumn{", n_col, "}{c}{", superheader, "} \\\\"),
    if (n_fe > 1) {
      paste0(" & ", paste(paste0("\\multicolumn{", n_fe, "}{c}{", oc_labels, "}"), collapse = " & "), " \\\\")
    } else {
      paste0(" & ", paste(paste0("\\multicolumn{1}{", centered, "}{", oc_labels, "}"), collapse = " & "), " \\\\")
    },
    paste0(" & ", paste(paste0("\\multicolumn{1}{", centered, "}{(", seq_len(n_col), ")}"), collapse = " & "), " \\\\")
  )

  # FE checkmark rows only when FEs differ across columns (formatting Rule 7);
  # otherwise the FEs are stated in the notes.
  fe_uniform <- length(unique(col_fe)) == 1
  fe_rows <- if (!fe_uniform) {
    fe_state <- grepl("STATE_CODE^year", col_fe, fixed = TRUE)
    fe_year  <- vapply(col_fe, function(fe) "year" %in% trimws(strsplit(fe, "\\+")[[1]]), logical(1))
    c("\\hline",
      paste0("Utility fixed effects & ", paste(rep("$\\checkmark$", n_col), collapse = " & "), " \\\\"),
      paste0("Year fixed effects & ", paste(ifelse(fe_year, "$\\checkmark$", ""), collapse = " & "), " \\\\"),
      paste0("State $\\times$ year fixed effects & ", paste(ifelse(fe_state, "$\\checkmark$", ""), collapse = " & "), " \\\\"))
  } else NULL
  fe_note <- if (fe_uniform) {
    if (grepl("STATE_CODE^year", col_fe[1], fixed = TRUE)) "All specifications include utility and state $\\times$ year fixed effects. "
    else "All specifications include utility and year fixed effects. "
  } else ""

  panel_block <- function(p, first, last) {
    tab <- c(
      paste0("\\begin{tabular}{", col_spec, "}"),
      if (first) c("\\toprule", header_block),
      "\\hline",
      paste0("\\multicolumn{", n_col + 1, "}{l}{", panel_titles[[p]], "} \\\\"),
      paste0(row_labs[[p]], " & ", paste(sapply(cells[[p]], `[[`, "coef"), collapse = " & "), " \\\\"),
      paste0(" & ", paste(sapply(cells[[p]], `[[`, "se"), collapse = " & "), " \\\\"),
      if (last) c(fe_rows, "\\bottomrule"),
      "\\end{tabular}"
    )
    c("\\begin{adjustbox}{max width=\\linewidth}", tab, "\\end{adjustbox}")
  }
  body <- unlist(lapply(seq_along(panels), function(i)
    panel_block(panels[i], first = i == 1, last = i == length(panels))))

  note <- paste0(
    "\\textit{Notes:} ", depvar_note, fe_note,
    "The sample has ", format(n_utils[1], big.mark = ","), " utilities and ",
    format(n_obs[1], big.mark = ","), " utility-year observations. ",
    "Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )

  lines <- c(
    "\\begin{table}[htbp]",
    "\\raggedright",
    "\\begin{minipage}{\\linewidth}",
    paste0("\\caption{\\label{", label, "} ", title, "}"),
    "\\end{minipage}",
    "\\small",
    "{\\setlength{\\tabcolsep}{4pt}%",
    body,
    "}",
    "\\begin{minipage}{\\linewidth}",
    "\\vspace{4pt}",
    "\\footnotesize",
    "\\raggedright",
    note,
    "\\end{minipage}",
    "\\end{table}"
  )
  out_path <- file.path(ROOT, "output/reg", paste0(outfile, "_placement.tex"))
  if (file.exists(out_path)) cat("  NOTE: overwriting", out_path, "\n")
  writeLines(lines, out_path)
  cat(sprintf("  Written: %s  (N = %d utilities / %d obs, F = %s)\n",
              out_path, n_utils[1], n_obs[1], paste(round(f_vals, 2), collapse = ", ")))
  invisible(list(iv_list = iv_list))
}

pp_note <- "Coefficients and standard errors are in percentage points. "

# ── MR violations (OLS, 2SLS, RF) ──────────────────────────────────────────
r_mr <- render_placement_k2(
  dat         = main_dat,
  outcomes    = c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic",
                  inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  fe_specs    = FE_TWO,
  outfile     = "2sls_dwnstrm_minevio_mr_ivsum_binvio_k2",
  title       = "Effect of coal mines on inorganic chemical violations at utilities",
  label       = "tab:2sls_dwnstrm_minevio_mr_ivsum_binvio_k2_placement",
  depvar_note = pp_note,
  panels      = c("ols", "iv", "rf"),
  superheader = "Monitoring and reporting (MR) violation"
)

# Anchor: nitrates state x year 2SLS must still equal 3.94 (1.75)
anc <- get_term(r_mr$iv_list[[2]], coalvar)
stopifnot(abs(round(anc$est, 2) - 3.94) < 0.01, abs(round(anc$se, 2) - 1.75) < 0.01)
cat("MR anchor gate PASSED.\n")

# ── Enforcement types (2SLS only) ──────────────────────────────────────────
render_placement_k2(
  dat         = main_dat,
  outcomes    = c(any_informal = "Informal", any_formal = "Formal", no_enf = "None"),
  fe_specs    = FE_TWO,
  outfile     = "h3_inf_formal_d12_k2",
  title       = "Effect of coal mining on enforcement actions by type",
  label       = "tab:h3_inf_formal_d12_k2_placement",
  depvar_note = pp_note,
  panels      = "iv",
  superheader = "Enforcement"
)

# ── Visit types (2SLS only) ────────────────────────────────────────────────
render_placement_k2(
  dat         = main_dat,
  outcomes    = c(any_snsv = "Sanitary", any_tech = "Technical assistance",
                  any_enfvisit = "Enforcement", any_smpl = "Sample collection",
                  any_insp = "Inspection"),
  fe_specs    = fe_state_yr,
  outfile     = "h2_snsv_d12_k2",
  title       = "Effect of coal mining on regulator visit probability by visit type",
  label       = "tab:h2_snsv_d12_k2_placement",
  depvar_note = pp_note,
  panels      = "iv"
)

cat("\n=== run_k2_placement_tables.r DONE ===\n")
