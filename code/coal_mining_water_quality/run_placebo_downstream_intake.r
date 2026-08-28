# ============================================================
# Script: run_placebo_downstream_intake.r
# Purpose: Downstream-of-intake mines falsification test. Re-runs the main
#          binary-violation 2SLS specification on a placebo treatment: coal
#          mines located in the HUC12 immediately downstream of a CWS intake
#          (contamination cannot flow upstream, so these mines cannot affect
#          the CWS's water). A null result supports the exclusion restriction
#          of the ARP instrument. Also runs an independent-samples z-test of
#          the placebo reduced-form estimate against the main-sample estimate.
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur_placebo_downstream_intake.parquet
#   clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs:
#   output/reg/2sls_placebo_dwnstrmintake_minevio_mr_ivsum_binvio.tex
#   output/reg/2sls_placebo_dwnstrmintake_minevio_mcl_ivsum_binvio.tex
#   output/reg/2sls_placebo_dwnstrmintake_minevio_allcat_ivsum_binvio.tex
#   output/reg/fs_placebo_dwnstrmintake_minevio_ivsum_binvio.tex
#   output/reg/2sls_placebo_dwnstrmintake_minevio_mr_ivsum_binvio_surfacewater.tex
#   output/reg/placebo_equivalence_downstream_intake.tex
# Author: EK  Date: 2026-08-28
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

placebo <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur_placebo_downstream_intake.parquet")
placebo <- placebo[placebo$year < 2006 & placebo$year > 1984, ]
str(placebo[, c("PWSID", "year")])
cat("Rows in placebo:", nrow(placebo), "\n")

main_d1 <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
main_d1 <- main_d1[main_d1$year < 2006 & main_d1$year > 1984, ]
main_d1 <- main_d1[main_d1$PWSID != "WV3303401", ]
main_d1 <- main_d1[(main_d1$minehuc_downstream_of_mine == 1) & (main_d1$minehuc_mine == 0), ]
cat("Rows in main D1 sample:", nrow(main_d1), "\n")

# ── Verification gate: placebo and main D1 samples must be disjoint CWS sets ──
overlap_pwsids <- intersect(unique(placebo$PWSID), unique(main_d1$PWSID))
if (length(overlap_pwsids) > 0) {
  stop("Placebo sample shares ", length(overlap_pwsids),
       " PWSID(s) with the main D1 sample - independence assumption for the z-test is violated: ",
       paste(head(overlap_pwsids, 5), collapse = ", "))
}
cat("Confirmed: placebo sample shares zero PWSIDs with the main D1 sample.\n")

# ── Construct binary outcomes (mirrors run_main_tables.r bin construction) ──
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
  placebo[[bv]] <- ifelse(is.na(placebo[[v]]), NA_integer_, as.integer(placebo[[v]] > 0))
  main_d1[[bv]] <- ifelse(is.na(main_d1[[v]]), NA_integer_, as.integer(main_d1[[v]] > 0))
}

# ── Helper functions (copied verbatim from run_main_tables.r) ────────────────
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

fs_fingerprint <- function(m) {
  paste(nobs(m),
        paste(names(coef(m)), collapse = "|"),
        paste(signif(coef(m), 10), collapse = "|"),
        paste(signif(se(m), 10), collapse = "|"),
        sep = "||")
}

set_adjustbox_width <- function(x, w) {
  x <- paste(x, collapse = "\n")
  sub("\\begin{adjustbox}{width = \\textwidth, center}",
      paste0("\\begin{adjustbox}{width = ", w, "\\textwidth, center}"),
      x, fixed = TRUE)
}

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
    f_clustered <- NA_real_
    if (!is.null(iv)) {
      f_fs <- as.formula(paste0(coalvar[1], " ~ ", instr_str, " + ", controls_str, " | ", fe_str))
      fs_cl <- tryCatch(fixest::feols(f_fs, data = dset_y, cluster = ~ PWSID), error = function(e) NULL)
      if (!is.null(fs_cl)) {
        t_cl <- coef(fs_cl)[instr_str] / se(fs_cl)[instr_str]
        f_clustered <- round(t_cl^2, 2)
      }
    }
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

  el        <- list(ifelse(is.na(f_vals), "", format(round(f_vals, 2), nsmall = 2)))
  names(el) <- "F-test (1st stage, clustered)"

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
    digits          = "r4",
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

has_variation <- function(dset, y) {
  v <- dset[[y]]
  v <- v[!is.na(v)]
  length(v) > 0L && length(unique(v)) > 1L
}

# ── Dictionary and specification ──────────────────────────────────────────
vio_dict_placebo <- c(
  num_coal_mines_downstream_intake_sum = "Downstream-of-intake coal mines (sum)",
  sulfur_downstream_intake_sum         = "Downstream-of-intake sulfur \\%",
  PWSID                                 = "CWS",
  nitrates_bin                          = "Nitrates",
  arsenic_bin                           = "Arsenic",
  inorganic_chemicals_bin               = "Inorganic chemicals",
  nitrates_MCL_bin                      = "Nitrates (MCL)",
  arsenic_MCL_bin                       = "Arsenic (MCL)",
  inorganic_chemicals_MCL_bin           = "Inorganic chemicals (MCL)",
  nitrates_MR_bin                       = "Nitrates (MR)",
  arsenic_MR_bin                        = "Arsenic (MR)",
  inorganic_chemicals_MR_bin            = "Inorganic chemicals (MR)"
)

coalvar   <- "num_coal_mines_downstream_intake_sum"
instr_str <- "post95:sulfur_downstream_intake_sum"

mr_vars     <- c("nitrates_MR_bin",  "arsenic_MR_bin",  "inorganic_chemicals_MR_bin")
mcl_vars    <- c("nitrates_MCL_bin", "arsenic_MCL_bin", "inorganic_chemicals_MCL_bin")
allcat_vars <- c("nitrates_bin",     "arsenic_bin",     "inorganic_chemicals_bin")

sample_note_txt <- paste0(
  "The sample is community water systems whose intake lies in the watershed immediately ",
  "upstream of a coal mine, excluding systems with any intake in a mining watershed or ",
  "downstream of one."
)

reg_note_txt <- paste0(
  "\\textit{Notes:} Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is an indicator equal to 1 if the CWS had any violation of that type during the year, 0 otherwise. ",
  "The instrument interacts an indicator for the post-1995 period with the sum of coal sulfur content ",
  "across watersheds immediately downstream of the CWS's intake. ",
  sample_note_txt, " ",
  "Standard errors clustered at the CWS level. ",
  "Sample period 1985--2005. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

fs_note_txt <- paste0(
  "\\textit{Notes:} The dependent variable is the number of coal mines in the watershed immediately ",
  "downstream of the community water system's intake. ",
  "The instrument interacts an indicator for the post-1995 period with the sum of coal sulfur content ",
  "across watersheds immediately downstream of the CWS's intake. ",
  sample_note_txt, " ",
  "Standard errors clustered at the CWS level. ",
  "Sample period 1985--2005. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

cat_specs <- list(
  list(name = "mr",     vars = mr_vars,     titlecat = "MR violations only"),
  list(name = "mcl",    vars = mcl_vars,    titlecat = "MCL violations only"),
  list(name = "allcat", vars = allcat_vars, titlecat = "any violation category")
)

# ── Step 2: Placebo regression tables ─────────────────────────────────────
fs_store_name <- "fs_store_placebo_dwnstrmintake_minevio"

for (cp in cat_specs) {
  fname     <- paste0("2sls_placebo_dwnstrmintake_minevio_", cp$name, "_ivsum_binvio")
  tab_title <- paste0("Effect of coal mines on IOC violations (", cp$titlecat, ", downstream-of-intake sample)")
  varlist   <- cp$vars[vapply(cp$vars, function(y) has_variation(placebo, y), logical(1))]
  for (y in setdiff(cp$vars, varlist)) cat("  Dropping", y, "- no variation in placebo sample\n")
  if (length(varlist) == 0) { cat("  No estimable outcomes for", cp$name, "- skipping table\n"); next }

  cat("\nRunning:", fname, "\n")
  tsls_reg_output_main(dset = placebo, varlist = varlist, coalvar = coalvar,
                       regoutname = fname, title = tab_title, label = fname,
                       instr_str = instr_str, dict = vio_dict_placebo, notes = reg_note_txt,
                       storage_list_name = fs_store_name, subheader = cp$titlecat,
                       fitstat = ~ n)
}

fs_outfile <- "fs_placebo_dwnstrmintake_minevio_ivsum_binvio"
cat("\nProducing first-stage table:", fs_outfile, "\n")
first_stage_table(
  storage_list_name = fs_store_name,
  outfile            = fs_outfile,
  title              = "First stage: effect of the Acid Rain Program on the number of downstream-of-intake coal mines",
  label              = paste0("tab:", fs_outfile),
  drop               = "num_facilities",
  dict               = vio_dict_placebo,
  notes              = fs_note_txt,
  fitstat            = ~ n
)

# ── Surface-water robustness (MR table) ───────────────────────────────────
sw_codes <- c("SW", "SWP")
dset_sw  <- placebo[placebo$PRIMARY_SOURCE_CODE %in% sw_codes, ]
cat("\nSurface-water placebo subsample:", nrow(dset_sw), "CWS-years,",
    length(unique(dset_sw$PWSID)), "CWSs\n")

sw_varlist <- mr_vars[vapply(mr_vars, function(y) has_variation(dset_sw, y), logical(1))]
for (y in setdiff(mr_vars, sw_varlist)) cat("  Dropping", y, "- no variation in surface-water subsample\n")

if (length(sw_varlist) > 0) {
  fname_sw <- "2sls_placebo_dwnstrmintake_minevio_mr_ivsum_binvio_surfacewater"
  reg_note_sw_txt <- paste0(
    "\\textit{Notes:} Columns show OLS, reduced form, and 2SLS estimates. ",
    "Dependent variable is an indicator equal to 1 if the CWS had any violation of that type during the year, 0 otherwise. ",
    "The instrument interacts an indicator for the post-1995 period with the sum of coal sulfur content ",
    "across watersheds immediately downstream of the CWS's intake. ",
    sample_note_txt, " ",
    "Sample further restricted to community water systems whose primary water source is surface water. ",
    "Standard errors clustered at the CWS level. ",
    "Sample period 1985--2005. ",
    "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )
  cat("\nRunning:", fname_sw, "\n")
  tsls_reg_output_main(dset = dset_sw, varlist = sw_varlist, coalvar = coalvar,
                       regoutname = fname_sw,
                       title = "Effect of coal mines on IOC violations (MR violations only, downstream-of-intake sample, surface water systems)",
                       label = fname_sw, instr_str = instr_str,
                       dict = vio_dict_placebo, notes = reg_note_sw_txt,
                       storage_list_name = NULL, subheader = NULL,
                       fitstat = ~ n)
} else {
  cat("  No estimable MR outcomes in surface-water subsample - skipping table\n")
}
cat("\nDone (placebo regression tables).\n")

# ── Step 3: Equivalence test against the main D1 estimate ────────────────
cat("\nStep 3: Equivalence test (placebo vs. main D1 reduced form)...\n")

equiv_rows <- list()
for (y in mr_vars) {
  f_plac <- as.formula(paste0(y, " ~ ", instr_str, " + num_facilities | PWSID + year"))
  f_main <- as.formula(paste0(y, " ~ post95:sulfur_unified_sum + num_facilities | PWSID + year"))

  rf_plac <- tryCatch(fixest::feols(f_plac, data = placebo[!is.na(placebo[[y]]), ], cluster = ~ PWSID),
                       error = function(e) { cat("  Placebo RF error", y, "-", conditionMessage(e), "\n"); NULL })
  rf_main <- tryCatch(fixest::feols(f_main, data = main_d1[!is.na(main_d1[[y]]), ], cluster = ~ PWSID),
                       error = function(e) { cat("  Main RF error", y, "-", conditionMessage(e), "\n"); NULL })

  if (is.null(rf_plac) || is.null(rf_main)) next

  g_plac  <- coef(rf_plac)[instr_str]
  se_plac <- se(rf_plac)[instr_str]
  g_main  <- coef(rf_main)["post95:sulfur_unified_sum"]
  se_main <- se(rf_main)["post95:sulfur_unified_sum"]

  ci_lo <- g_plac - 1.96 * se_plac
  ci_hi <- g_plac + 1.96 * se_plac

  z <- (g_main - g_plac) / sqrt(se_main^2 + se_plac^2)
  p <- 2 * (1 - pnorm(abs(z)))

  outside_ci <- (g_main < ci_lo) || (g_main > ci_hi)

  equiv_rows[[y]] <- data.frame(
    outcome = vio_dict_placebo[[y]],
    g_plac = g_plac, se_plac = se_plac, ci_lo = ci_lo, ci_hi = ci_hi,
    g_main = g_main, se_main = se_main,
    z = z, p = p, outside_ci = outside_ci
  )
  cat(sprintf("  %-25s g_plac=%.4f (SE %.4f)  g_main=%.4f (SE %.4f)  z=%.3f  p=%.4f  main outside placebo 95%% CI: %s\n",
              y, g_plac, se_plac, g_main, se_main, z, p, outside_ci))
}

equiv_df <- if (length(equiv_rows) > 0) do.call(rbind, equiv_rows) else NULL

fmt4 <- function(x) format(round(x, 4), nsmall = 4)
fmt3 <- function(x) format(round(x, 3), nsmall = 3)

equiv_lines <- c(
  "\\begin{table}[htbp]",
  "   \\caption{\\label{tab:placebo_equivalence_downstream_intake} Equivalence test: downstream-of-intake reduced-form estimate vs.\\ main-sample estimate}",
  "   \\centering",
  "   \\begin{adjustbox}{width = \\textwidth, center}",
  "   \\begin{tabular}{lccccc}",
  "   \\toprule",
  "    & Downstream-of-intake estimate (95\\% CI) & Main-sample estimate & $z$ & $p$ & Main outside 95\\% CI \\\\",
  "   \\midrule"
)
if (!is.null(equiv_df)) {
  for (i in seq_len(nrow(equiv_df))) {
    r <- equiv_df[i, ]
    ci_str <- paste0(fmt4(r$g_plac), " [", fmt4(r$ci_lo), ", ", fmt4(r$ci_hi), "]")
    main_str <- paste0(fmt4(r$g_main), " (", fmt4(r$se_main), ")")
    flag_str <- if (isTRUE(r$outside_ci)) "Yes" else "No"
    equiv_lines <- c(equiv_lines,
      paste0("   ", r$outcome, " & ", ci_str, " & ", main_str, " & ",
             fmt3(r$z), " & ", fmt4(r$p), " & ", flag_str, " \\\\"))
  }
}
equiv_lines <- c(equiv_lines,
  "   \\bottomrule",
  "   \\end{tabular}",
  "   \\end{adjustbox}",
  "   {\\tiny\\linespread{1}\\selectfont \\par \\raggedright",
  paste0("   \\textit{Notes:} Downstream-of-intake estimates are reduced-form coefficients ",
         "(post-1995 indicator interacted with the sum of coal sulfur content across watersheds ",
         "immediately downstream of the CWS's intake) with 95\\% confidence intervals in brackets. ",
         "Main-sample estimates are reduced-form coefficients from the corresponding specification ",
         "estimated on community water systems at most one watershed downstream of a coal mine, using ",
         "post-1995 interacted with the sum of coal sulfur content across upstream watersheds. ",
         "The two samples share no community water systems in common, so the $z$-statistic treats the ",
         "two estimates as independent. Standard errors clustered at the CWS level. Sample period 1985--2005.}"),
  "\\end{table}"
)
writeLines(equiv_lines, "Z:/ek559/mining_wq/output/reg/placebo_equivalence_downstream_intake.tex")
cat("\nWritten output/reg/placebo_equivalence_downstream_intake.tex\n")

cat("\nDone.\n")
