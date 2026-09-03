.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]
full$minehuc_upstream_of_mine[full$minehuc_upstream_of_mine == 1] <- "Upstream of mining"
full$minehuc_upstream_of_mine[full$minehuc_upstream_of_mine == 0] <- "Colocated/Downstream of mining"
cat("Rows in full:", nrow(full), "\n")

# 2-step downstream sample (CWSs 2 HUC12s downstream of a mine)
two_step_path <- "Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur_2step.parquet"
if (file.exists(two_step_path)) {
  full_2s <- read_parquet(two_step_path)
  full_2s <- full_2s[full_2s$year < 2006 & full_2s$year > 1984, ]
  full_2s <- full_2s[full_2s$PWSID != "WV3303401", ]
  full_2s$minehuc_upstream_of_mine[full_2s$minehuc_upstream_of_mine == 1] <- "Upstream of mining"
  full_2s$minehuc_upstream_of_mine[full_2s$minehuc_upstream_of_mine == 0] <- "Colocated/Downstream of mining"
  cat("Rows in full_2s:", nrow(full_2s), "\n")
  full_expanded <- dplyr::bind_rows(full, full_2s)
  cat("Rows in full_expanded:", nrow(full_expanded), "\n")
} else {
  warning("prod_vio_sulfur_2step.parquet not found - dwnstrm2step spec will be skipped")
  full_expanded <- full
}

vio_dict <- c(
  nitrates_share_days                      = "Nitrates",
  arsenic_share_days                       = "Arsenic",
  inorganic_chemicals_share_days           = "Inorganic chemicals",
  radionuclides_share_days                 = "Radionuclides",
  nitrates_MCL_share_days                  = "Nitrates (MCL)",
  arsenic_MCL_share_days                   = "Arsenic (MCL)",
  inorganic_chemicals_MCL_share_days       = "Inorganic chemicals (MCL)",
  radionuclides_MCL_share_days             = "Radionuclides (MCL)",
  nitrates_MR_share_days                   = "Nitrates (MR)",
  arsenic_MR_share_days                    = "Arsenic (MR)",
  inorganic_chemicals_MR_share_days        = "Inorganic chemicals (MR)",
  radionuclides_MR_share_days              = "Radionuclides (MR)",
  total_coliform_share_days                = "Total coliform",
  voc_share_days                           = "VOCs",
  total_coliform_MCL_share_days            = "Total coliform (MCL)",
  voc_MCL_share_days                       = "VOCs (MCL)",
  total_coliform_MR_share_days             = "Total coliform (MR)",
  voc_MR_share_days                        = "VOCs (MR)",
  num_coal_mines_upstream_sum              = "Upstream coal mines (sum)",
  sulfur_unified_sum                       = "Upstream sulfur \\%",
  PWSID                                    = "CWS"
)

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

# Two stored first stages are the same regression when the estimation sample and
# every coefficient / standard error coincide; used to drop redundant columns.
fs_fingerprint <- function(m) {
  paste(nobs(m),
        paste(names(coef(m)), collapse = "|"),
        paste(signif(coef(m), 10), collapse = "|"),
        paste(signif(se(m), 10), collapse = "|"),
        sep = "||")
}

# etable's adjustbox always writes width = \textwidth, which blows a one- or
# two-column table up to full page width. Narrow it after the fact.
set_adjustbox_width <- function(x, w) {
  x <- paste(x, collapse = "\n")
  sub("\\begin{adjustbox}{width = \\textwidth, center}",
      paste0("\\begin{adjustbox}{width = ", w, "\\textwidth, center}"),
      x, fixed = TRUE)
}

# Replace the auto-numbered column row "(1) (2) (3) ..." with cycling OLS / RF / 2SLS.
rename_col_numbers_to_labels <- function(x) {
  x     <- paste(x, collapse = "\n")
  lines <- strsplit(x, "\n")[[1]]
  for (i in seq_along(lines)) {
    nums <- regmatches(lines[i], gregexpr("\\(\\d+\\)", lines[i]))[[1]]
    if (length(nums) >= 2) {
      num_vals <- as.integer(gsub("[()]", "", nums))
      if (identical(num_vals, seq_along(num_vals))) {
        labels <- rep(c("OLS", "RF", "2SLS"), length.out = length(nums))
        line   <- lines[i]
        for (j in seq_along(nums)) line <- sub(nums[j], labels[j], line, fixed = TRUE)
        lines[i] <- line
      }
    }
  }
  paste(lines, collapse = "\n")
}

# Right-align the model-coefficient columns of the generated tabular preamble
# (fixest's default is centered, which does not decimal-align numbers of
# differing digit-width) while leaving the leading row-label column ('l')
# untouched. Operates only on the exact matched preamble substring so it
# cannot touch \multicolumn{n}{c}{...} header spanning cells elsewhere.
right_align_tabular <- function(x) {
  x <- paste(x, collapse = "\n")
  m <- regmatches(x, regexpr("\\\\begin\\{tabular\\}\\{l+c+\\}", x))
  if (length(m) == 1 && nzchar(m)) {
    x <- sub(m, gsub("c", "r", m), x, fixed = TRUE)
  }
  x
}

postprocess_table <- function(x) right_align_tabular(rename_col_numbers_to_labels(move_notes_below_adjustbox(x)))

tsls_reg_output_main <- function(dset, varlist, coalvar, regoutname, title, label,
                                  instr_str, dict = NULL, notes = NULL,
                                  notes_present = NULL,
                                  storage_list_name = NULL, subheader = NULL,
                                  fitstat = ~ ., panel_style = FALSE,
                                  superheader = NULL) {
  controls            <- c("num_facilities")
  drop_controls_exact <- paste0("^(", paste(controls, collapse = "|"), ")$")
  fe_str              <- "PWSID + year"
  controls_str        <- paste(controls, collapse = " + ")
  result <- list()

  for (y in varlist) {
    # Subset to non-missing rows for this outcome so N reflects actual sample
    dset_y <- dset[!is.na(dset[[y]]), ]
    cat("  Outcome:", y, "| n =", nrow(dset_y), "\n")
    f_ols <- as.formula(paste0(y, " ~ ", paste(coalvar, collapse="+"), " + ", controls_str, " | ", fe_str))
    f_rf  <- as.formula(paste0(y, " ~ ", instr_str, " + ", controls_str, " | ", fe_str))
    f_iv  <- as.formula(paste0(y, " ~ ", controls_str, " | ", fe_str, " | ", paste(coalvar, collapse="+"), " ~ ", instr_str))
    ols <- tryCatch(fixest::feols(f_ols, data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  OLS error", y, "-", conditionMessage(e), "\n"); NULL })
    rf  <- tryCatch(fixest::feols(f_rf,  data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  RF error",  y, "-", conditionMessage(e), "\n"); NULL })
    iv  <- tryCatch(fixest::feols(f_iv,  data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  IV error",  y, "-", conditionMessage(e), "\n"); NULL })
    # Clustered first-stage F-stat: run first stage explicitly with cluster=~PWSID
    # fixest's ivf1 uses HC1 SEs internally; t^2 from the clustered regression is correct
    f_clustered <- NA_real_
    if (!is.null(iv)) {
      f_fs <- as.formula(paste0(coalvar[1], " ~ ", instr_str, " + ", controls_str, " | ", fe_str))
      fs_cl <- tryCatch(fixest::feols(f_fs, data = dset_y, cluster = ~ PWSID), error = function(e) NULL)
      if (!is.null(fs_cl)) {
        t_cl <- coef(fs_cl)[instr_str] / se(fs_cl)[instr_str]
        f_clustered <- round(t_cl^2, 2)
      }
    }
    # Only include outcome if all three models succeeded
    if (!is.null(ols) && !is.null(rf) && !is.null(iv)) {
      result[[y]] <- list(OLS = ols, RF = rf, IV = iv, f_clustered = f_clustered)
    } else {
      cat("  Dropping", y, "- not all three models succeeded\n")
    }
  }

  if (length(result) == 0) {
    cat("  No estimable outcomes for", regoutname, "- skipping etable.\n")
    return(invisible(NULL))
  }

  # ── Persist first stages to global list ──────────────────────────────────
  if (!is.null(storage_list_name) && !is.null(subheader)) {
    if (!exists(storage_list_name, envir = .GlobalEnv)) {
      assign(storage_list_name, list(), envir = .GlobalEnv)
    }
    fs_list <- get(storage_list_name, envir = .GlobalEnv)
    if (is.null(fs_list[[subheader]])) {
      fs_list[[subheader]] <- list()
    }
    for (y in names(result)) {
      for (cv in coalvar) {
        fs_list[[subheader]][[y]][[cv]] <- list(
          model       = result[[y]]$IV$iv_first_stage[[cv]],
          f_clustered = result[[y]]$f_clustered
        )
      }
    }
    assign(storage_list_name, fs_list, envir = .GlobalEnv)
  }

  if (panel_style) {
    render_panel_binary_table(result = result, dict = dict, coalvar = coalvar,
                               instr_str = instr_str, title = title, label = label,
                               outfile = regoutname, superheader = superheader)
    # Presentation companion: same panels, notes stripped to FE + clustering +
    # stars only (see .claude/logs/2026-08-31-presentation-notes-tables.md).
    if (!is.null(notes_present)) {
      render_panel_binary_table(result = result, dict = dict, coalvar = coalvar,
                                 instr_str = instr_str, title = title, label = label,
                                 outfile = paste0(regoutname, "_present"),
                                 notes = notes_present, superheader = superheader)
    }
    return(invisible(NULL))
  }

  model_list <- unlist(
    lapply(names(result), function(y) list(result[[y]]$OLS, result[[y]]$RF, result[[y]]$IV)),
    recursive = FALSE
  )
  # Build extralines: clustered F-stat in IV columns only, blank in OLS/RF columns
  coalvar_labels <- sapply(coalvar, function(cv) if (!is.null(dict) && cv %in% names(dict)) dict[[cv]] else cv)
  f_label <- paste0("F-test (1st stage, clustered), ", paste(coalvar_labels, collapse = "+"))
  f_vec   <- unlist(lapply(names(result), function(y) {
    fc <- result[[y]]$f_clustered
    c("", "", if (is.na(fc)) "" else format(round(fc, 2), nsmall = 2))
  }))
  el        <- list(f_vec)
  names(el) <- f_label
  etable_args <- c(
    model_list,
    list(
      fitstat         = fitstat,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      digits          = "r4",
      drop            = drop_controls_exact,
      drop.section    = "fixef",
      title           = title,
      label           = label,
      postprocess.tex = postprocess_table,
      extralines      = el,
      file            = paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex")
    )
  )
  if (!is.null(dict))  etable_args$dict  <- dict
  if (!is.null(notes)) etable_args$notes <- notes
  do.call(etable, etable_args)
}

first_stage_table <- function(storage_list_name, outfile, title = NULL,
                               label = NULL, which_coalvar = NULL,
                               drop = NULL, dict = NULL, notes = NULL,
                               notes_present = NULL,
                               fitstat = ~ n) {
  fs_list      <- get(storage_list_name, envir = .GlobalEnv)
  model_list   <- list()
  f_vals       <- numeric(0)
  col_depvars  <- character(0)
  col_subheads <- character(0)
  seen         <- character(0)

  for (subheader in names(fs_list)) {
    depvar_bucket <- fs_list[[subheader]]
    for (depvar in names(depvar_bucket)) {
      coal_models <- depvar_bucket[[depvar]]
      cv    <- if (!is.null(which_coalvar)) which_coalvar else names(coal_models)[1]
      entry <- coal_models[[cv]]
      fp    <- fs_fingerprint(entry$model)
      # The outcome does not enter the first stage, so columns sharing a sample
      # and an instrument are the identical regression - keep only the first.
      if (fp %in% seen) next
      seen         <- c(seen, fp)
      model_list   <- c(model_list, list(entry$model))
      f_vals       <- c(f_vals, entry$f_clustered)
      col_depvars  <- c(col_depvars, depvar)
      col_subheads <- c(col_subheads, subheader)
    }
  }
  if (length(model_list) == 0) {
    cat("  No stored first stages for", storage_list_name, "- skipping.\n")
    return(invisible(NULL))
  }
  cat("  First-stage columns after collapsing duplicates:", length(model_list), "\n")

  # Clustered first-stage F, matching the value reported in the 2SLS tables.
  el        <- list(ifelse(is.na(f_vals), "", format(round(f_vals, 2), nsmall = 2)))
  names(el) <- "F-test (1st stage, clustered)"

  # Column headers only make sense when more than one distinct first stage survives.
  # Built as plain character vectors (one entry per column) rather than named
  # span lists: fixest's span-list form (list("label" = span)) mis-renders when
  # a header row reduces to a single group, which happens routinely here once
  # duplicate columns are dropped. A character vector lets fixest handle the
  # multicolumn spanning itself and is robust to that case.
  headers_arg <- NULL
  if (length(model_list) > 1) {
    translate_depvar <- function(v) if (!is.null(dict) && v %in% names(dict)) dict[[v]] else v
    outer_vec   <- col_subheads
    inner_vec   <- vapply(col_depvars, translate_depvar, character(1), USE.NAMES = FALSE)
    headers_arg <- list(outer_vec, inner_vec)
  }

  box_width <- if (length(model_list) <= 2) 0.45 else 1
  post_fun  <- function(x) {
    x <- right_align_tabular(move_notes_below_adjustbox(x))
    if (box_width < 1) x <- set_adjustbox_width(x, box_width)
    x
  }

  etable_args <- list(
    fitstat         = fitstat,
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    digits          = "r4",
    drop            = drop,
    drop.section    = "fixef",
    title           = title,
    label           = label,
    extralines      = el,
    postprocess.tex = post_fun,
    file            = paste0("Z:/ek559/mining_wq/output/reg/", outfile, ".tex")
  )
  if (!is.null(headers_arg)) etable_args$headers <- headers_arg
  if (!is.null(dict))        etable_args$dict    <- dict
  if (!is.null(notes))       etable_args$notes   <- notes
  do.call(etable, c(model_list, etable_args))

  # Presentation companion: same table, notes stripped to FE + clustering +
  # stars only (see .claude/logs/2026-08-31-presentation-notes-tables.md).
  if (!is.null(notes_present)) {
    etable_args_present         <- etable_args
    etable_args_present$notes   <- notes_present
    etable_args_present$file    <- sub("\\.tex$", "_present.tex",
                                        etable_args$file)
    do.call(etable, c(model_list, etable_args_present))
  }
}

# ── Panel-style table for a binary-violation MR/2SLS table ──────────────────
# Stacks OLS / reduced form / 2SLS as three vertically-stacked panels (one
# tabular per panel) instead of side-by-side columns, so each panel shows
# only the coefficient that model actually estimates (RF loads on the
# instrument, OLS/2SLS load on the endogenous coal-mine count). Coefficient
# and SE cells are phantom-padded to a common integer-digit width and a
# common 3-star slot so the decimal points of the coefficient and its SE
# line up vertically within a column. Follows the same multipanel rules as
# violation_binary_days_panels.r: a thick \toprule at the very top of the
# first panel and a thick \bottomrule at the very bottom of the last panel;
# single \hline for every
# other internal rule, so the three tabulars read as one table.
fmt_num_wide <- function(est, se, pval, w, digits = 2) {
  # Reserve a sign slot for both lines of the pair (real "-" or a matching
  # \phantom{-}) so a negative coefficient's minus sign does not shift its
  # digits - and therefore its decimal point - out of alignment with the
  # (always non-negative) standard error printed directly below it. `w` is
  # the shared integer-digit width computed across ALL three panels for this
  # column (see fmt_col()), so decimal points line up down the whole column,
  # not just within one panel's coefficient/SE pair.
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

# Formats one outcome column's OLS/RF/IV coefficient+SE pairs together, padding
# all six numbers to a single shared integer-digit width so the decimal point
# aligns down the entire column across the three stacked panels.
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
  # fixest's 2SLS models report the endogenous regressor's coefficient under
  # a "fit_<var>" row name rather than the bare variable name.
  row <- if (term %in% rownames(ct)) term else paste0("fit_", term)
  if (row %in% rownames(ct)) {
    list(est = ct[row, "Estimate"], se = ct[row, "Std. Error"], pval = ct[row, "Pr(>|t|)"])
  } else {
    list(est = NA_real_, se = NA_real_, pval = NA_real_)
  }
}

render_panel_binary_table <- function(result, dict, coalvar, instr_str, title, label, outfile, notes = NULL, superheader = NULL) {
  y_vec    <- names(result)
  n_y      <- length(y_vec)
  y_labels <- sapply(y_vec, function(v) if (!is.null(dict) && v %in% names(dict)) dict[[v]] else v)
  # Superheader already communicates whether a table is MCL- or MR-only, so
  # per-column "(MCL)"/"(MR)" suffixes are redundant here.
  y_labels <- gsub(" \\(MCL\\)$", "", y_labels)
  y_labels <- gsub(" \\(MR\\)$",  "", y_labels)
  coal_lab <- if (!is.null(dict) && coalvar %in% names(dict)) dict[[coalvar]] else coalvar

  instr_parts     <- strsplit(instr_str, ":")[[1]]
  instr_lab_parts <- sapply(instr_parts, function(p) if (!is.null(dict) && p %in% names(dict)) dict[[p]] else p)
  instr_lab       <- paste(instr_lab_parts, collapse = " $\\times$ ")

  # Fixed-width columns (rather than content-driven "l"/"r") so the same
  # outcome lands at the same horizontal position in every panel, even
  # though each panel's tabular is a separate environment with its own
  # row-label text ("Upstream coal mines (sum)" vs. the longer instrument
  # interaction label).
  # Data columns are capped at 3cm each (the width tuned for the 3-outcome
  # tables) but shrink further for tables with more outcome columns so the
  # table never exceeds the 16.51cm text width (12pt article, 1in margins).
  label_w_cm <- 5.5
  max_w_cm   <- 16
  data_w_cm  <- min(3, (max_w_cm - label_w_cm) / n_y)
  label_w    <- paste0(label_w_cm, "cm")
  data_w     <- paste0(data_w_cm, "cm")
  col_spec   <- paste0("p{", label_w, "}",
                        paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w, "}"), n_y), collapse = ""))

  # Column headings and column numbers are centered (the data columns
  # underneath stay right-aligned for decimal alignment), via a per-cell
  # \multicolumn override of the column's default alignment. The override
  # keeps the column's fixed p{} width (wrapping long headers like
  # "Technical assistance" onto a second line) rather than the unconstrained
  # "c" LaTeX would otherwise size to content - an unconstrained cell here
  # would make this row's tabular wider than the other panels', so a
  # per-panel adjustbox (see wrap_panel() below) scales it down more than
  # the panels underneath and the column numbers stop aligning across models.
  centered_data_col <- paste0(">{\\centering\\arraybackslash}p{", data_w, "}")
  header_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{", y_labels, "}")
  header_row   <- paste0(" & ", paste(header_cells, collapse = " & "), " \\\\")
  colnum_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{(", seq_len(n_y), ")}")
  # Column numbers appear once for the whole table, directly under the
  # column-heading row and above the rule that sets off the first panel.
  colnum_row   <- paste0(" & ", paste(colnum_cells, collapse = " & "), " \\\\")
  # Each panel's title row names its model, spanning the full table width.
  title_row <- function(model_label) {
    paste0("\\multicolumn{", n_y + 1, "}{l}{", model_label, "} \\\\")
  }

  # Superheader spans only the data columns (not the row-label column), with
  # a partial rule (\cline) underneath so the rule does not run under the
  # label column.
  superheader_lines <- if (!is.null(superheader)) {
    c(paste0(" & \\multicolumn{", n_y, "}{c}{", superheader, "} \\\\"),
      paste0("\\cline{2-", n_y + 1, "}"))
  } else {
    NULL
  }

  ols_terms <- lapply(y_vec, function(y) get_term(result[[y]]$OLS, coalvar))
  rf_terms  <- lapply(y_vec, function(y) get_term(result[[y]]$RF,  instr_str))
  iv_terms  <- lapply(y_vec, function(y) get_term(result[[y]]$IV,  coalvar))
  f_vals    <- sapply(y_vec, function(y) result[[y]]$f_clustered)

  col_fmts  <- lapply(seq_len(n_y), function(j) fmt_col(ols_terms[[j]], rf_terms[[j]], iv_terms[[j]]))
  ols_cells <- lapply(col_fmts, `[[`, "ols")
  rf_cells  <- lapply(col_fmts, `[[`, "rf")
  iv_cells  <- lapply(col_fmts, `[[`, "iv")

  coef_line <- function(cells, row_label) {
    paste0(row_label, " & ", paste(sapply(cells, `[[`, "coef"), collapse = " & "), " \\\\")
  }
  se_line <- function(cells) {
    paste0(" & ", paste(sapply(cells, `[[`, "se"), collapse = " & "), " \\\\")
  }

  # Physical width of the tabular exceeds the sum of the p{} column widths by
  # the \tabcolsep padding LaTeX inserts around every column (measured
  # empirically: sum(col widths) + 2*(ncols)*tabcolsep). When that exceeds the
  # document's text width (12pt article, 1in margins), scale each panel's
  # tabular down via adjustbox per CLAUDE.md's multi-panel-table convention
  # instead of narrowing columns.
  tabcolsep_pt    <- 4
  cm_per_pt       <- 2.54 / 72.27
  textwidth_cm    <- 16.51
  intercol_pad_cm <- 2 * (n_y + 1) * tabcolsep_pt * cm_per_pt
  natural_w_cm    <- label_w_cm + n_y * data_w_cm + intercol_pad_cm
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

  # Panel order: OLS, then 2SLS, then reduced form. Each panel carries a
  # title row naming its model (rather than "Panel A/B/C"); every internal
  # rule is a full-width \hline (the only partial rule in the table is the
  # \cline under the superheader).
  panel_ols <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\toprule",
    superheader_lines,
    header_row,
    colnum_row,
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
    "\\bottomrule",
    "\\end{tabular}"
  ))

  n_obs  <- unique(sapply(y_vec, function(y) nobs(result[[y]]$IV)))
  n_note <- if (length(n_obs) == 1) {
    paste0("Number of observations = ", format(n_obs, big.mark = ","), ".")
  } else {
    paste0("Number of observations ranges from ", format(min(n_obs), big.mark = ","),
           " to ", format(max(n_obs), big.mark = ","), " across outcomes.")
  }

  f_unique <- unique(round(f_vals, 2))
  f_note   <- if (length(f_unique) == 1) {
    paste0("The first-stage F-statistic (clustered at the utility level) for the instrumented ",
           "variable, ", coal_lab, ", is ", fmt_single(f_unique), ".")
  } else {
    paste0("The first-stage F-statistic (clustered at the utility level) for the instrumented ",
           "variable, ", coal_lab, ", ranges from ", fmt_single(min(f_vals)),
           " to ", fmt_single(max(f_vals)), " across outcomes.")
  }

  note_text <- if (!is.null(notes)) notes else paste0(
    "\\textit{Notes:} Dependent variable equals 1 if the utility had any violation of that type ",
    "during the year, 0 otherwise; coefficients and standard errors multiplied by 100 to show ",
    "percentage point change. The instrument interacts an indicator for the post-1995 period with ",
    "the sum of coal sulfur content across upstream watersheds. All specifications include ",
    "utilities and year fixed effects. Standard errors clustered at the utilities level. ",
    f_note, " ",
    "Sample period 1985--2005. ", n_note, " ",
    "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )

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

  out_path <- paste0("Z:/ek559/mining_wq/output/reg/", outfile, ".tex")
  writeLines(table_lines, out_path)
  cat("  Panel table written to:", out_path, "\n")
}

std_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is days out of the year in violation. ",
  "Instrument is post95 interacted with mean coal sulfur content of the intake watershed ",
  "(post95 x sulfur_unified_mean). ",
  "All regressions include CWS and year fixed effects. ",
  "Standard errors clustered at CWS level. ",
  "Sample period 1985--2005."
)

std_note_ivsum <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is days out of the year in violation. ",
  "Instrument is post95 interacted with sum of coal sulfur content across upstream HUC12s ",
  "(post95 x sulfur_unified_sum). ",
  "All regressions include CWS and year fixed effects. ",
  "Standard errors clustered at CWS level. ",
  "Sample period 1985--2005."
)

nonmine_note <- paste0(
  std_note,
  " The number of observations differs across columns because non-mining violation rules ",
  "(total coliform, VOCs) were implemented during the sample period; ",
  "years prior to each rule's implementation are coded as missing and excluded from the regression."
)

nonmine_note_ivsum <- paste0(
  std_note_ivsum,
  " The number of observations differs across columns because non-mining violation rules ",
  "(total coliform, VOCs) were implemented during the sample period; ",
  "years prior to each rule's implementation are coded as missing and excluded from the regression."
)

sample_specs <- list(
  list(sample="dwnstrm",        suffix="",       dset=full[(full$minehuc_downstream_of_mine==1)&(full$minehuc_mine==0),],            coalvar="num_coal_mines_upstream_mean", instr="post95:sulfur_unified_mean", titlesamp="CWSs at most one HUC12 down-stream",                notesamp="community water systems at most one watershed downstream of a coal mine"),
  list(sample="dwnstrm",        suffix="_ivsum", dset=full[(full$minehuc_downstream_of_mine==1)&(full$minehuc_mine==0),],            coalvar="num_coal_mines_upstream_sum",  instr="post95:sulfur_unified_sum",  titlesamp="CWSs at most one HUC12 down-stream",                notesamp="community water systems at most one watershed downstream of a coal mine"),
  list(sample="dwnstrmcolocate",suffix="",       dset=full[full$minehuc_upstream_of_mine=="Colocated/Downstream of mining",], coalvar="num_coal_mines_unified_mean",  instr="post95:sulfur_unified_mean", titlesamp="downstream and colocated PWS's",                    notesamp="community water systems colocated with or downstream of a coal mine"),
  list(sample="dwnstrm2step",   suffix="",       dset=full_expanded[(full_expanded$minehuc_downstream_of_mine==1)&(full_expanded$minehuc_mine==0),], coalvar="num_coal_mines_upstream_mean", instr="post95:sulfur_unified_mean", titlesamp="CWSs at most two HUC12's downstream of coal mines", notesamp="community water systems at most two watersheds downstream of a coal mine"),
  list(sample="dwnstrm2step",   suffix="_ivsum", dset=full_expanded[(full_expanded$minehuc_downstream_of_mine==1)&(full_expanded$minehuc_mine==0),], coalvar="num_coal_mines_upstream_sum",  instr="post95:sulfur_unified_sum",  titlesamp="CWSs at most two HUC12's downstream of coal mines", notesamp="community water systems at most two watersheds downstream of a coal mine")
)

# Plain-language notes for first-stage tables (see table-notes-conventions.md: no variable names).
fs_note <- function(is_sum, notesamp) {
  agg <- if (is_sum) "sum of coal sulfur content across upstream watersheds" else
                     "mean coal sulfur content of the intake watershed"
  dep <- if (is_sum) "summed across upstream watersheds" else
                     "averaged across upstream watersheds"
  paste0(
    "\\textit{Notes:} The dependent variable is the number of coal mines in watersheds upstream ",
    "of the community water system's intake, ", dep, ". ",
    "The instrument interacts an indicator for the post-1995 period with the ", agg, ". ",
    "The sample is ", notesamp, ". ",
    "All specifications include CWS and year fixed effects. ",
    "Standard errors clustered at the CWS level. ",
    "Sample period 1985--2005. ",
    "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )
}
vio_specs <- list(
  list(name="minevio",    allcat=c("nitrates_share_days","arsenic_share_days","inorganic_chemicals_share_days","radionuclides_share_days"),             mcl=c("nitrates_MCL_share_days","arsenic_MCL_share_days","inorganic_chemicals_MCL_share_days","radionuclides_MCL_share_days"),             mr=c("nitrates_MR_share_days","arsenic_MR_share_days","inorganic_chemicals_MR_share_days","radionuclides_MR_share_days"),             titlevio="IOC violations"),
  list(name="nonminevio", allcat=c("total_coliform_share_days","voc_share_days"),                mcl=c("total_coliform_MCL_share_days","voc_MCL_share_days"),                mr=c("total_coliform_MR_share_days","voc_MR_share_days"),                titlevio="non-mining violations")
)
cat_specs <- list(
  list(name="allcat", varkey="allcat", titlecat="any violation category"),
  list(name="mcl",    varkey="mcl",    titlecat="MCL violations only"),
  list(name="mr",     varkey="mr",     titlecat="MR violations only")
)

for (sp in sample_specs) {
  for (vp in vio_specs) {
    fs_store_name <- paste0("fs_store_", sp$sample, sp$suffix, "_", vp$name)
    for (cp in cat_specs) {
      fname     <- paste0("2sls_", sp$sample, "_", vp$name, "_", cp$name, sp$suffix)
      tab_title <- paste0("Effect of coal mines on ", vp$titlevio, " (", cp$titlecat, ", ", sp$titlesamp, ")")
      varlist   <- vp[[cp$varkey]]
      cat("\nRunning:", fname, "\n")
      tab_note    <- if (vp$name == "nonminevio") {
        if (sp$suffix == "_ivsum") nonmine_note_ivsum else nonmine_note
      } else {
        if (sp$suffix == "_ivsum") std_note_ivsum else std_note
      }
      tab_fitstat <- if (sp$suffix == "_ivsum") ~ n else ~ .
      tsls_reg_output_main(dset=sp$dset, varlist=varlist, coalvar=sp$coalvar,
                           regoutname=fname, title=tab_title, label=fname,
                           instr_str=sp$instr, dict=vio_dict, notes=tab_note,
                           storage_list_name = fs_store_name,
                           subheader         = cp$titlecat,
                           fitstat           = tab_fitstat)
    }
    fs_outfile <- paste0("fs_", sp$sample, "_", vp$name, sp$suffix)
    fs_agg     <- if (sp$suffix == "_ivsum") "summed across upstream watersheds" else "averaged across upstream watersheds"
    fs_title   <- paste0("First stage: effect of the Acid Rain Program on the number of upstream coal mines (",
                         fs_agg, ", ", sp$titlesamp, ")")
    cat("\nProducing first-stage table:", fs_outfile, "\n")
    # Presentation companion only for the one first-stage table used in
    # main.tex (fs_dwnstrm_minevio_ivsum) — see
    # .claude/logs/2026-08-31-presentation-notes-tables.md.
    fs_notes_present <- if (fs_outfile == "fs_dwnstrm_minevio_ivsum") {
      paste0("\\textit{Notes:} All specifications include CWS and year fixed effects. ",
             "Standard errors clustered at the CWS level. ",
             "*** p$<$0.01, ** p$<$0.05, * p$<$0.1.")
    } else NULL
    first_stage_table(
      storage_list_name = fs_store_name,
      outfile           = fs_outfile,
      title             = fs_title,
      label             = paste0("tab:", fs_outfile),
      drop              = "num_facilities",
      dict              = vio_dict,
      notes             = fs_note(sp$suffix == "_ivsum", sp$notesamp),
      notes_present     = fs_notes_present,
      fitstat           = if (sp$suffix == "_ivsum") ~ n else ~ .
    )
  }
}
cat("\nDone.\n")

# ── Binary violation tables (dwnstrm + _ivsum spec only) ─────────────────────
# Create 0/1 indicators: 1 if the CWS had any days in violation during the year.
# NA preserved where _share_days is NA (pre-rule years for non-mining outcomes).
bin_src_vars <- c(
  "nitrates_share_days", "arsenic_share_days",
  "inorganic_chemicals_share_days", "radionuclides_share_days",
  "nitrates_MCL_share_days", "arsenic_MCL_share_days",
  "inorganic_chemicals_MCL_share_days", "radionuclides_MCL_share_days",
  "nitrates_MR_share_days", "arsenic_MR_share_days",
  "inorganic_chemicals_MR_share_days", "radionuclides_MR_share_days"
)
# Coded 0/100 rather than 0/1 so that every OLS/RF/2SLS coefficient and SE
# estimated on these outcomes is already in percentage-point units (a linear
# rescaling of the dependent variable rescales coefficients/SEs identically
# and leaves F-stats, R^2, and t-stats unchanged).
for (v in bin_src_vars) {
  bv <- sub("_share_days$", "_bin", v)
  full[[bv]]          <- ifelse(is.na(full[[v]]),          NA_integer_, as.integer(full[[v]] > 0) * 100L)
  full_expanded[[bv]] <- ifelse(is.na(full_expanded[[v]]), NA_integer_, as.integer(full_expanded[[v]] > 0) * 100L)
}

vio_dict_bin <- c(
  vio_dict,
  nitrates_bin                      = "Nitrates",
  arsenic_bin                       = "Arsenic",
  inorganic_chemicals_bin           = "Inorganic chemicals",
  radionuclides_bin                 = "Radionuclides",
  nitrates_MCL_bin                  = "Nitrates (MCL)",
  arsenic_MCL_bin                   = "Arsenic (MCL)",
  inorganic_chemicals_MCL_bin       = "Inorganic chemicals (MCL)",
  radionuclides_MCL_bin             = "Radionuclides (MCL)",
  nitrates_MR_bin                   = "Nitrates (MR)",
  arsenic_MR_bin                    = "Arsenic (MR)",
  inorganic_chemicals_MR_bin        = "Inorganic chemicals (MR)",
  radionuclides_MR_bin              = "Radionuclides (MR)"
)

std_note_ivsum_bin <- paste0(
  "\\textit{Notes:} Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable equals 100 if the CWS had any violation of that type during the year, 0 otherwise; ",
  "coefficients and standard errors are in percentage points. ",
  "The instrument interacts an indicator for the post-1995 period with the sum of coal sulfur content ",
  "across upstream watersheds. ",
  "All specifications include CWS and year fixed effects. ",
  "Standard errors clustered at the CWS level. ",
  "Sample period 1985--2005. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

vio_specs_bin <- list(
  list(name="minevio",
       allcat = c("nitrates_bin", "arsenic_bin", "inorganic_chemicals_bin"),
       mcl    = c("nitrates_MCL_bin", "arsenic_MCL_bin", "inorganic_chemicals_MCL_bin"),
       mr     = c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin"),
       titlevio = "IOC violations")
)

bin_sample_specs <- list(
  list(sample="dwnstrm", suffix="_ivsum", coalvar="num_coal_mines_upstream_sum",
       instr="post95:sulfur_unified_sum", titlesamp="CWSs at most one HUC12 down-stream",
       notesamp="community water systems at most one watershed downstream of a coal mine",
       dset=full[(full$minehuc_downstream_of_mine==1) & (full$minehuc_mine==0), ])
)

for (sp in bin_sample_specs) {
  for (vp in vio_specs_bin) {
    fs_store_name <- paste0("fs_store_", sp$sample, sp$suffix, "_", vp$name, "_bin")
    for (cp in cat_specs) {
      fname           <- paste0("2sls_", sp$sample, "_", vp$name, "_", cp$name, sp$suffix, "_binvio")
      # All three category cuts (any violation / MCL / MR) of the main
      # dwnstrm+_ivsum binary spec render as panel-style tables so their
      # main.tex entries share one consistent (portrait) layout.
      is_panel_target <- TRUE
      tab_title       <- switch(cp$name,
        allcat = "Effect of coal mines on inorganic chemical violations at utilities",
        mcl    = "Effect of coal mines on inorganic chemical maximum contaminant level violations at utilities",
        mr     = "Effect of coal mines on inorganic chemical monitoring and reporting violations at utilities",
        paste0("Effect of coal mines on ", vp$titlevio, " (", cp$titlecat, ", ", sp$titlesamp, ")")
      )
      varlist   <- vp[[cp$varkey]]
      # The superheader names the violation-category cut this table is
      # restricted to; it spans just the outcome columns underneath it.
      tab_superheader <- switch(cp$name,
        allcat = "Any violation",
        mcl    = "Any MCL violation",
        mr     = "Any MR violation"
      )
      cat("\nRunning:", fname, "\n")
      # Presentation companion: notes stripped to FE + clustering + stars
      # only (see .claude/logs/2026-08-31-presentation-notes-tables.md).
      bin_notes_present <- paste0(
        "\\textit{Notes:} All specifications include utilities and year fixed effects. ",
        "Standard errors clustered at the utilities level. ",
        "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
      )
      tsls_reg_output_main(dset=sp$dset, varlist=varlist, coalvar=sp$coalvar,
                           regoutname=fname, title=tab_title, label=fname,
                           instr_str=sp$instr, dict=vio_dict_bin, notes=std_note_ivsum_bin,
                           notes_present=bin_notes_present,
                           storage_list_name=fs_store_name,
                           subheader=cp$titlecat,
                           fitstat=~ n,
                           panel_style=is_panel_target,
                           superheader=tab_superheader)
    }
    fs_outfile <- paste0("fs_", sp$sample, "_", vp$name, sp$suffix, "_binvio")
    fs_title   <- paste0("First stage: effect of the Acid Rain Program on the number of upstream coal mines (",
                         "summed across upstream watersheds, ", sp$titlesamp, ")")
    cat("\nProducing first-stage table:", fs_outfile, "\n")
    first_stage_table(
      storage_list_name=fs_store_name,
      outfile=fs_outfile,
      title=fs_title,
      label=paste0("tab:", fs_outfile),
      drop="num_facilities",
      dict=vio_dict_bin,
      notes=fs_note(TRUE, sp$notesamp),
      fitstat=~ n
    )
  }
}
cat("\nDone (binary violation tables).\n")

# ── Surface-water subsample: binary violation tables (dwnstrm + _ivsum spec only) ──
# Re-estimates the three binary-violation tables above on the subsample of CWSs
# whose primary water source is surface water, to test whether the main results
# are driven by surface-water or groundwater systems.
has_variation <- function(dset, y) {
  v <- dset[[y]]
  v <- v[!is.na(v)]
  length(v) > 0L && length(unique(v)) > 1L
}

std_note_ivsum_bin_sw <- paste0(
  "\\textit{Notes:} Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable equals 100 if the CWS had any violation of that type during the year, 0 otherwise; ",
  "coefficients and standard errors are in percentage points. ",
  "The instrument interacts an indicator for the post-1995 period with the sum of coal sulfur content ",
  "across upstream watersheds. ",
  "Sample further restricted to community water systems whose primary water source is surface water. ",
  "All specifications include CWS and year fixed effects. ",
  "Standard errors clustered at the CWS level. ",
  "Sample period 1985--2005. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

sw_codes <- c("SW", "SWP")
dset_sw  <- full[(full$minehuc_downstream_of_mine == 1) &
                 (full$minehuc_mine == 0) &
                 (full$PRIMARY_SOURCE_CODE %in% sw_codes), ]
cat("\nSurface-water D1 subsample:", nrow(dset_sw), "CWS-years,",
    length(unique(dset_sw$PWSID)), "CWSs\n")

for (cp in cat_specs) {
  vp        <- vio_specs_bin[[1]]
  varlist   <- vp[[cp$varkey]]
  keep      <- vapply(varlist, function(y) has_variation(dset_sw, y), logical(1))
  for (y in varlist[!keep]) cat("  Dropping", y, "- no variation in surface-water subsample\n")
  varlist   <- varlist[keep]
  if (length(varlist) == 0) { cat("  No estimable outcomes for", cp$name, "- skipping table\n"); next }

  fname     <- paste0("2sls_dwnstrm_minevio_", cp$name, "_ivsum_binvio_surfacewater")
  tab_title <- paste0("Effect of coal mines on ", vp$titlevio, " (", cp$titlecat,
                      ", CWSs at most one HUC12 down-stream, surface water systems)")
  cat("\nRunning:", fname, "\n")
  tsls_reg_output_main(dset = dset_sw, varlist = varlist,
                       coalvar   = "num_coal_mines_upstream_sum",
                       regoutname = fname, title = tab_title, label = fname,
                       instr_str = "post95:sulfur_unified_sum",
                       dict = vio_dict_bin, notes = std_note_ivsum_bin_sw,
                       storage_list_name = NULL, subheader = NULL,
                       fitstat = ~ n)
}
cat("\nDone (surface-water binary violation tables).\n")
