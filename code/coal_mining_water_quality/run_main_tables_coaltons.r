# ============================================================
# Script: run_main_tables_coaltons.r
# Purpose: Reproduce the ivsum downstream binary-violation 2SLS tables and
#          their first-stage table with upstream coal PRODUCTION (short tons,
#          summed across upstream HUC12s, scaled to millions) as the
#          endogenous variable, in place of the upstream coal mine count.
#          Instrument is unchanged (post95 x sulfur_unified_sum).
# Inputs: clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs:
#   output/reg/fs_dwnstrm_minevio_ivsumcoaltons.tex
#   output/reg/2sls_dwnstrm_minevio_allcat_ivsumcoaltons_binvio.tex
#   output/reg/2sls_dwnstrm_minevio_mr_ivsumcoaltons_binvio.tex
#   output/reg/2sls_dwnstrm_minevio_mcl_ivsumcoaltons_binvio.tex
# Author: EK  Date: 2026-08-27
# ============================================================

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

# Scaled endogenous variable: millions of short tons (raw tons give unreadable
# ~1e-8 coefficients).
full$production_short_tons_coal_upstream_sum_mil <-
  full$production_short_tons_coal_upstream_sum / 1e6
cat(sprintf("production_short_tons_coal_upstream_sum_mil: mean = %.4f, NAs = %d\n",
    mean(full$production_short_tons_coal_upstream_sum_mil, na.rm = TRUE),
    sum(is.na(full$production_short_tons_coal_upstream_sum_mil))))

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
  production_short_tons_coal_upstream_sum_mil     = "Upstream coal production (mil. short tons)",
  fit_production_short_tons_coal_upstream_sum_mil = "Upstream coal production (mil. short tons)",
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

postprocess_table <- function(x) rename_col_numbers_to_labels(move_notes_below_adjustbox(x))

tsls_reg_output_main <- function(dset, varlist, coalvar, regoutname, title, label,
                                  instr_str, dict = NULL, notes = NULL,
                                  storage_list_name = NULL, subheader = NULL,
                                  fitstat = ~ .) {
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
      drop            = drop_controls_exact,
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
    x <- move_notes_below_adjustbox(x)
    if (box_width < 1) x <- set_adjustbox_width(x, box_width)
    x
  }

  etable_args <- list(
    fitstat         = fitstat,
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    drop            = drop,
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
}

# Plain-language notes for the first-stage table (see table-notes-conventions.md:
# no variable names).
fs_note_coaltons <- paste0(
  "\\textit{Notes:} The dependent variable is coal production, in millions of short ",
  "tons, summed across the watersheds directly upstream of the community water ",
  "system's intake. ",
  "The instrument interacts an indicator for the post-1995 period with the sum of ",
  "coal sulfur content across upstream watersheds. ",
  "The sample is community water systems at most one watershed downstream of a coal mine. ",
  "Standard errors clustered at the CWS level. ",
  "Sample period 1985--2005. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

# ── Binary violation tables (dwnstrm + ivsumcoaltons spec only) ─────────────
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
for (v in bin_src_vars) {
  bv <- sub("_share_days$", "_bin", v)
  full[[bv]] <- ifelse(is.na(full[[v]]), NA_integer_, as.integer(full[[v]] > 0))
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

std_note_coaltons_bin <- paste0(
  "\\textit{Notes:} Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is an indicator equal to 1 if the CWS had any violation of that type during the year, 0 otherwise. ",
  "The endogenous regressor is coal production, in millions of short tons, summed across the watersheds directly upstream of the CWS intake. ",
  "The instrument interacts an indicator for the post-1995 period with the sum of coal sulfur content ",
  "across upstream watersheds. ",
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

cat_specs <- list(
  list(name="allcat", varkey="allcat", titlecat="any violation category"),
  list(name="mcl",    varkey="mcl",    titlecat="MCL violations only"),
  list(name="mr",     varkey="mr",     titlecat="MR violations only")
)

bin_sample_specs <- list(
  list(sample="dwnstrm", suffix="_ivsumcoaltons",
       coalvar="production_short_tons_coal_upstream_sum_mil",
       instr="post95:sulfur_unified_sum",
       titlesamp="CWSs at most one HUC12 down-stream",
       notesamp="community water systems at most one watershed downstream of a coal mine",
       dset=full[(full$minehuc_downstream_of_mine==1) & (full$minehuc_mine==0), ])
)

for (sp in bin_sample_specs) {
  for (vp in vio_specs_bin) {
    fs_store_name <- paste0("fs_store_", sp$sample, sp$suffix, "_", vp$name, "_bin")
    for (cp in cat_specs) {
      fname     <- paste0("2sls_", sp$sample, "_", vp$name, "_", cp$name, sp$suffix, "_binvio")
      tab_title <- paste0("Effect of coal production on ", vp$titlevio, " (", cp$titlecat, ", ", sp$titlesamp, ")")
      varlist   <- vp[[cp$varkey]]
      cat("\nRunning:", fname, "\n")
      tsls_reg_output_main(dset=sp$dset, varlist=varlist, coalvar=sp$coalvar,
                           regoutname=fname, title=tab_title, label=fname,
                           instr_str=sp$instr, dict=vio_dict_bin, notes=std_note_coaltons_bin,
                           storage_list_name=fs_store_name,
                           subheader=cp$titlecat,
                           fitstat=~ n)
    }
    cat("\nProducing first-stage table: fs_dwnstrm_minevio_ivsumcoaltons\n")
    first_stage_table(
      storage_list_name = fs_store_name,
      outfile           = "fs_dwnstrm_minevio_ivsumcoaltons",
      title             = paste0("First stage: effect of the Acid Rain Program on upstream coal production ",
                                 "(summed across upstream watersheds, ", sp$titlesamp, ")"),
      label             = "tab:fs_dwnstrm_minevio_ivsumcoaltons",
      drop              = "num_facilities",
      dict              = vio_dict_bin,
      notes             = fs_note_coaltons,
      fitstat           = ~ n
    )
  }
}
cat("\nDone (coal-tons binary violation tables).\n")
