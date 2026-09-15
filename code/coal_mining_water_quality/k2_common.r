# ============================================================
# Script: k2_common.r
# Purpose: Shared helpers for the k=2 A-full step-instrument-grid table
#          set (run_k2_main_tables.r, run_k2_placebo_tables.r,
#          run_k2_sum_tables.r, run_k2_6yr_tables.r, run_k2_figures.r):
#          panel construction, the display-label dictionary, coefficient
#          formatting helpers (ported verbatim from run_main_tables.r),
#          the clustered first-stage F helper, the grouped-outcome panel
#          table renderer, and the table-notes string builder. Read-only
#          against step_instruments.parquet / cws_covariates_steps.parquet
#          / sdwa_vio_agg_steps.parquet / sdwa_visit_agg_k2.parquet /
#          sdwa_enf_agg_k2.parquet.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_data/cws_covariates_steps.parquet
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet
# Outputs: none (sourced by run_k2_*.r scripts)
# Author: EK  Date: 2026-09-14
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"

# ── 1. Panel construction ────────────────────────────────────────────────
# Builds the joined, zero-filled, x100-scaled k=2 A-full panel for one arm.
# Mirrors run_step_instrument_grid.r:38-64, with the visit/enforcement
# sources swapped for the k2 caches (5 visit flags + any_enf, vs. the
# 2-flag/no-any_enf `_steps` caches) and the sample restricted to k=2,
# A-full (n_mine_hucs_linked >= 1, no n_hucs_covered filter), per plan 0.1.
build_k2_panel <- function(arm_choice = c("main", "placebo")) {
  arm_choice <- match.arg(arm_choice)

  si     <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
  covars <- read_parquet(file.path(ROOT, "clean_data/cws_data/cws_covariates_steps.parquet"))
  vio    <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_vio_agg_steps.parquet"))
  visit  <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_visit_agg_k2.parquet"))
  enf    <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_enf_agg_k2.parquet"))

  stopifnot(is.character(si$PWSID), is.character(covars$PWSID),
            is.character(vio$PWSID), is.character(visit$PWSID), is.character(enf$PWSID))

  panel <- covars %>%
    dplyr::left_join(vio,   by = c("PWSID", "year")) %>%
    dplyr::left_join(visit, by = c("PWSID", "year")) %>%
    dplyr::left_join(enf,   by = c("PWSID", "year"))

  vio_share_cols <- grep("_share_days$", names(panel), value = TRUE)
  for (v in vio_share_cols) panel[[v]][is.na(panel[[v]])] <- 0
  zero_fill_cols <- c("n_visits", "any_snsv", "any_tech", "any_enfvisit", "any_smpl",
                       "any_insp", "any_formal", "any_informal", "any_enf")
  for (v in zero_fill_cols) panel[[v]][is.na(panel[[v]])] <- 0

  # Binary outcomes coded 0/100 (percentage points), table-figure-formatting.md Rule 6.
  # Any-category `_bin` outcomes are not built by run_step_instrument_grid.r (it builds
  # only MR/MCL) -- constructed here from `<contam>_share_days` (plan Step 4.1).
  bin_src_vars <- c(
    "nitrates_share_days", "arsenic_share_days", "inorganic_chemicals_share_days",
    "nitrates_MCL_share_days", "arsenic_MCL_share_days", "inorganic_chemicals_MCL_share_days",
    "nitrates_MR_share_days", "arsenic_MR_share_days", "inorganic_chemicals_MR_share_days"
  )
  for (v in bin_src_vars) {
    bv <- sub("_share_days$", "_bin", v)
    panel[[bv]] <- as.integer(panel[[v]] > 0) * 100L
  }
  for (v in c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp",
              "any_formal", "any_informal", "any_enf")) {
    panel[[v]] <- panel[[v]] * 100
  }
  panel$no_enf  <- 100 - panel$any_enf
  panel$post95  <- as.integer(panel$year >= 1995)

  full <- si %>% dplyr::inner_join(panel, by = c("PWSID", "year"))

  main_k2 <- full %>% dplyr::filter(arm == "main", k == 2, n_mine_hucs_linked >= 1)
  if (arm_choice == "main") {
    out <- main_k2
  } else {
    main_ids <- unique(main_k2$PWSID)
    out <- full %>% dplyr::filter(arm == "placebo", k == 2, n_mine_hucs_linked >= 1,
                                   !(PWSID %in% main_ids))
  }
  cat(sprintf("k2 %s panel: %d rows, %d utilities\n",
              arm_choice, nrow(out), dplyr::n_distinct(out$PWSID)))
  out
}

# ── 2. Display-label dictionary (CLAUDE.md glossary -> capitalized label) ──
# "utilities", never "CWS"/"PWS" (plan Step 0.6); (MR)/(MCL) suffix stripped
# from outcome labels since the table superheader already carries it.
k2_dict <- c(
  PWSID                          = "Utility",
  num_coal_mines_linked_sum      = "Upstream coal mines (sum)",
  post95                         = "Post-1995",
  sulfur_mean0                   = "Upstream sulfur \\%",
  num_facilities                 = "Number of intake facilities",
  nitrates_bin                   = "Nitrates",
  arsenic_bin                    = "Arsenic",
  inorganic_chemicals_bin        = "Inorganic chemicals",
  nitrates_MR_bin                = "Nitrates",
  arsenic_MR_bin                 = "Arsenic",
  inorganic_chemicals_MR_bin     = "Inorganic chemicals",
  nitrates_MCL_bin               = "Nitrates",
  arsenic_MCL_bin                = "Arsenic",
  inorganic_chemicals_MCL_bin    = "Inorganic chemicals",
  any_snsv                       = "Sanitary",
  any_tech                       = "Technical assistance",
  any_enfvisit                   = "Enforcement",
  any_smpl                       = "Sample collection",
  any_insp                       = "Inspection",
  any_informal                   = "Informal",
  any_formal                     = "Formal",
  no_enf                         = "None",
  VALUE                          = "Mean conc.",
  coal_prod_upstream_cumsum_10mst = "Cumul. upstream coal prod. (10M ST)"
)

# ── 3. Coefficient formatting helpers (verbatim, run_main_tables.r:345-393) ──
fmt_num_wide <- function(est, se, pval, w, digits = 2) {
  sign_coef <- if (est < 0) "-" else "\\phantom{-}"
  num       <- sprintf(paste0("%.", digits, "f"), abs(est))
  se_num    <- sprintf(paste0("%.", digits, "f"), se)
  int_w  <- function(s) nchar(sub("\\..*$", "", s))
  pad_to <- function(s) {
    cur <- int_w(s)
    if (cur < w) paste0(strrep("\\phantom{0}", w - cur), s) else s
  }
  num    <- pad_to(num)
  se_num <- pad_to(se_num)
  stars_n <- if (is.na(pval)) 0L else if (pval < 0.01) 3L else if (pval < 0.05) 2L else if (pval < 0.1) 1L else 0L
  stars_render <- paste0(vapply(1:3, function(i) if (i <= stars_n) "*" else "\\phantom{*}", character(1)), collapse = "")
  list(
    coef = paste0("\\phantom{(}", sign_coef, num, "$^{", stars_render, "}$"),
    se   = paste0("(", "\\phantom{-}", se_num, ")\\phantom{$^{***}$}")
  )
}

fmt_col <- function(ols_t, rf_t, iv_t, digits = 2) {
  int_w <- function(x) {
    if (is.na(x)) return(0L)
    nchar(sub("\\..*$", "", sprintf(paste0("%.", digits, "f"), abs(x))))
  }
  w <- max(int_w(ols_t$est), int_w(ols_t$se),
           int_w(rf_t$est),  int_w(rf_t$se),
           int_w(iv_t$est),  int_w(iv_t$se))
  list(
    ols = fmt_num_wide(ols_t$est, ols_t$se, ols_t$pval, w, digits),
    rf  = fmt_num_wide(rf_t$est,  rf_t$se,  rf_t$pval,  w, digits),
    iv  = fmt_num_wide(iv_t$est,  iv_t$se,  iv_t$pval,  w, digits)
  )
}

fmt_single <- function(x, digits = 2) sprintf(paste0("%.", digits, "f"), x)

get_term <- function(model, term) {
  ct <- fixest::coeftable(model)
  row <- if (term %in% rownames(ct)) term else paste0("fit_", term)
  if (row %in% rownames(ct)) {
    list(est = ct[row, "Estimate"], se = ct[row, "Std. Error"], pval = ct[row, "Pr(>|t|)"])
  } else {
    list(est = NA_real_, se = NA_real_, pval = NA_real_)
  }
}

# ── 4. Clustered first stage F (never fixest's ivf1 -- HC1, wrong here) ────
# Explicit (coef/se)^2 on post95:sulfur_mean0, exactly as
# run_step_instrument_grid.r:88-99.
f_clustered <- function(dat, fe_str) {
  fs <- tryCatch(
    fixest::feols(as.formula(paste0("num_coal_mines_linked_sum ~ post95:sulfur_mean0 + num_facilities | ", fe_str)),
                  data = dat, cluster = ~PWSID, warn = FALSE, notes = FALSE),
    error = function(e) NULL
  )
  if (is.null(fs) || !("post95:sulfur_mean0" %in% names(coef(fs)))) return(NA_real_)
  fs_coef <- coef(fs)["post95:sulfur_mean0"]
  fs_se   <- fixest::se(fs)["post95:sulfur_mean0"]
  round((fs_coef / fs_se)^2, 2)
}

# ── 5. Table-notes string builder ───────────────────────────────────────
# Every k2 table has FE checkmark rows in its body (Utility/Year/State x
# year), so per table-notes-conventions.md Rule 7 the notes say nothing
# about fixed effects. `depvar_sentence` must avoid variable names and
# describe the outcome/instrument in plain language (Step 0.7 terminology:
# "within two flow steps upstream", never "colocated + downstream").
notes_k2 <- function(depvar_sentence, f_note = NULL, extra = NULL) {
  paste0(
    "\\textit{Notes:} ", depvar_sentence, " ",
    "Standard errors clustered at the utility level. ",
    if (!is.null(f_note)) paste0(f_note, " ") else "",
    "Sample period 1985--2005. ",
    if (!is.null(extra)) paste0(extra, " ") else "",
    "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )
}

# ── 5b. etable() post-processing helpers (verbatim, run_main_tables.r) ─────
move_notes_below_adjustbox <- function(x) {
  x <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj, paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ", trimws(note_block), "}"), x, fixed = TRUE)
  x
}

right_align_tabular <- function(x) {
  x <- paste(x, collapse = "\n")
  m <- regmatches(x, regexpr("\\\\begin\\{tabular\\}\\{l+c+\\}", x))
  if (length(m) == 1 && nzchar(m)) {
    x <- sub(m, gsub("c", "r", m), x, fixed = TRUE)
  }
  x
}

# ── 6. Panel table renderer ──────────────────────────────────────────────
# Generalizes run_main_tables.r's render_panel_binary_table (lines 495-714)
# to a list of (outcome, FE spec) column specs, grouped by outcome with a
# multicolumn superheader + cline when more than one FE spec is supplied
# per outcome (collapses to the original one-column-per-outcome layout when
# fe_specs has length 1 -- h2/h3 tables, plan Step 4.6/4.7).
render_panel_k2 <- function(dat, outcomes, fe_specs, dict,
                             coalvar = "num_coal_mines_linked_sum",
                             instr_str = "post95:sulfur_mean0",
                             title, label, outfile,
                             depvar_sentence, extra_note = NULL, superheader = NULL) {
  n_oc  <- length(outcomes)
  n_fe  <- length(fe_specs)
  n_col <- n_oc * n_fe

  oc_labels <- unname(sapply(names(outcomes), function(v) if (v %in% names(dict)) dict[[v]] else v))
  coal_lab  <- if (coalvar %in% names(dict)) dict[[coalvar]] else coalvar
  instr_parts <- strsplit(instr_str, ":")[[1]]
  instr_lab   <- paste(sapply(instr_parts, function(p) if (p %in% names(dict)) dict[[p]] else p), collapse = " $\\times$ ")

  col_oc <- rep(names(outcomes), each = n_fe)
  col_fe <- rep(fe_specs, times = n_oc)

  ols_list <- vector("list", n_col); rf_list <- vector("list", n_col); iv_list <- vector("list", n_col)
  f_vals   <- numeric(n_col); n_utils <- integer(n_col); n_obs <- integer(n_col)

  for (j in seq_len(n_col)) {
    oc <- col_oc[j]; fe <- col_fe[j]
    dat_y <- dat[!is.na(dat[[oc]]), ]
    f_ols <- as.formula(paste0(oc, " ~ ", coalvar, " + num_facilities | ", fe))
    f_rf  <- as.formula(paste0(oc, " ~ ", instr_str, " + num_facilities | ", fe))
    f_iv  <- as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", coalvar, " ~ ", instr_str))
    ols_list[[j]] <- fixest::feols(f_ols, data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    rf_list[[j]]  <- fixest::feols(f_rf,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    iv_list[[j]]  <- fixest::feols(f_iv,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    f_vals[j]     <- f_clustered(dat_y, fe)
    n_utils[j]    <- length(fixest::fixef(iv_list[[j]])$PWSID)
    n_obs[j]      <- nobs(iv_list[[j]])
  }

  ols_terms <- lapply(seq_len(n_col), function(j) get_term(ols_list[[j]], coalvar))
  rf_terms  <- lapply(seq_len(n_col), function(j) get_term(rf_list[[j]],  instr_str))
  iv_terms  <- lapply(seq_len(n_col), function(j) get_term(iv_list[[j]],  coalvar))

  label_w_cm <- 5.5
  max_w_cm   <- 16
  data_w_cm  <- min(3, (max_w_cm - label_w_cm) / n_col)
  label_w    <- paste0(label_w_cm, "cm")
  data_w     <- paste0(data_w_cm, "cm")
  col_spec   <- paste0("p{", label_w, "}",
                        paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w, "}"), n_col), collapse = ""))
  centered_data_col <- paste0(">{\\centering\\arraybackslash}p{", data_w, "}")

  superheader_lines <- if (!is.null(superheader)) {
    c(paste0(" & \\multicolumn{", n_col, "}{c}{", superheader, "} \\\\"),
      paste0("\\cline{2-", n_col + 1, "}"))
  } else NULL

  if (n_fe > 1) {
    grp_header_cells <- paste0("\\multicolumn{", n_fe, "}{c}{", oc_labels, "}")
    grp_header_row   <- paste0(" & ", paste(grp_header_cells, collapse = " & "), " \\\\")
    cline_parts <- vapply(seq_len(n_oc), function(i) {
      start <- 2 + (i - 1) * n_fe
      end   <- 1 + i * n_fe
      sprintf("\\cline{%d-%d}", start, end)
    }, character(1))
    cline_row <- paste(cline_parts, collapse = " ")
    colnum_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{(", seq_len(n_col), ")}")
    colnum_row   <- paste0(" & ", paste(colnum_cells, collapse = " & "), " \\\\")
    header_block <- c(grp_header_row, cline_row, colnum_row)
  } else {
    header_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{", oc_labels, "}")
    header_row   <- paste0(" & ", paste(header_cells, collapse = " & "), " \\\\")
    colnum_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{(", seq_len(n_col), ")}")
    colnum_row   <- paste0(" & ", paste(colnum_cells, collapse = " & "), " \\\\")
    header_block <- c(header_row, colnum_row)
  }

  title_row <- function(model_label) paste0("\\multicolumn{", n_col + 1, "}{l}{", model_label, "} \\\\")

  col_fmts  <- lapply(seq_len(n_col), function(j) fmt_col(ols_terms[[j]], rf_terms[[j]], iv_terms[[j]]))
  ols_cells <- lapply(col_fmts, `[[`, "ols")
  rf_cells  <- lapply(col_fmts, `[[`, "rf")
  iv_cells  <- lapply(col_fmts, `[[`, "iv")

  coef_line <- function(cells, row_label) paste0(row_label, " & ", paste(sapply(cells, `[[`, "coef"), collapse = " & "), " \\\\")
  se_line   <- function(cells) paste0(" & ", paste(sapply(cells, `[[`, "se"), collapse = " & "), " \\\\")

  fe_state     <- vapply(col_fe, function(fe) grepl("STATE_CODE^year", fe, fixed = TRUE), logical(1))
  chk_all      <- paste(rep("$\\checkmark$", n_col), collapse = " & ")
  chk_state    <- paste(ifelse(fe_state, "$\\checkmark$", ""), collapse = " & ")
  fe_row_util  <- paste0("Utility fixed effects & ", chk_all, " \\\\")
  fe_row_year  <- paste0("Year fixed effects & ", chk_all, " \\\\")
  fe_row_state <- paste0("State $\\times$ year fixed effects & ", chk_state, " \\\\")
  n_util_row   <- paste0("Utilities & ", paste(format(n_utils, big.mark = ","), collapse = " & "), " \\\\")
  n_obs_row    <- paste0("Utility-years & ", paste(format(n_obs, big.mark = ","), collapse = " & "), " \\\\")

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
    coef_line(ols_cells, coal_lab),
    se_line(ols_cells),
    "\\end{tabular}"
  ))
  panel_iv <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline",
    title_row("2SLS"),
    coef_line(iv_cells, coal_lab),
    se_line(iv_cells),
    "\\end{tabular}"
  ))
  panel_rf <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline",
    title_row("RF"),
    coef_line(rf_cells, instr_lab),
    se_line(rf_cells),
    "\\hline",
    fe_row_util, fe_row_year, fe_row_state,
    n_util_row, n_obs_row,
    "\\bottomrule",
    "\\end{tabular}"
  ))

  f_unique <- unique(round(f_vals, 2))
  f_note <- if (length(f_unique) == 1) {
    paste0("The first-stage F-statistic (clustered at the utility level) for the instrumented ",
           "variable, ", coal_lab, ", is ", fmt_single(f_unique), ".")
  } else {
    paste0("The first-stage F-statistic (clustered at the utility level) for the instrumented ",
           "variable, ", coal_lab, ", ranges from ", fmt_single(min(f_vals)),
           " to ", fmt_single(max(f_vals)), " across columns.")
  }
  note_text <- notes_k2(depvar_sentence, f_note = f_note, extra = extra_note)

  table_lines <- c(
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
    note_text,
    "\\end{minipage}",
    "\\end{table}"
  )

  out_path <- file.path(ROOT, "output/reg", paste0(outfile, ".tex"))
  writeLines(table_lines, out_path)
  cat("  k2 panel table written to:", out_path, "\n")
  invisible(list(f_vals = f_vals, n_utils = n_utils, n_obs = n_obs,
                 iv_list = iv_list, rf_list = rf_list, ols_list = ols_list))
}
