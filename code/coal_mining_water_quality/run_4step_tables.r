# ============================================================
# Script: run_4step_tables.r
# Purpose: Run main 2SLS regressions on progressively expanding downstream
#          samples (D1, D1+D2, D1+D2+D3, D1+D2+D3+D4) from the 4step parquet.
#          Produces one mining-violation table and one non-mining-violation
#          table per sample increment. Also prints a console summary comparing
#          the D2 subsample against prod_vio_sulfur_2step.parquet to verify
#          sample construction consistency.
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur_4step.parquet
#   clean_data/cws_data/prod_vio_sulfur_2step.parquet
# Outputs:
#   output/reg/2sls_4step_d{N}_minevio_mcl.tex   (N = 1, 2, 3, 4)
#   output/reg/2sls_4step_d{N}_nonminevio_mcl.tex
# Author: EK  Date: 2026-04-27
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(dplyr)

# ── Load data ─────────────────────────────────────────────────────────────────
step4 <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur_4step.parquet")
step4 <- step4[step4$year < 2006 & step4$year > 1984, ]
step4 <- step4[step4$PWSID != "WV3303401", ]
cat("Rows in step4 (1985-2005):", nrow(step4), "\n")
cat("CWSs in step4:", length(unique(step4$PWSID)), "\n")
cat("downstream_step distribution:\n")
print(table(step4$downstream_step))

# ── Composite outcomes ─────────────────────────────────────────────────────────
# MCL composite: sum of MCL days for 4 mining contaminants
step4$mining_health_MCL_share_days <- (
  step4$nitrates_MCL_share_days +
  step4$arsenic_MCL_share_days +
  step4$inorganic_chemicals_MCL_share_days +
  step4$radionuclides_MCL_share_days
)

# Health-based composite: EPA IS_HEALTH_BASED_IND flag, aggregated over 4 mining contaminants
step4$mining_health_based_share_days <- (
  step4$nitrates_health_share_days +
  step4$arsenic_health_share_days +
  step4$inorganic_chemicals_health_share_days +
  step4$radionuclides_health_share_days
)

cat("MCL composite > 0:", sum(step4$mining_health_MCL_share_days > 0, na.rm = TRUE), "\n")
cat("Health-based composite > 0:", sum(step4$mining_health_based_share_days > 0, na.rm = TRUE), "\n")

# ── Validate D2 subsample against prod_vio_sulfur_2step.parquet ───────────────
cat("\n========== Sample consistency check ==========\n")
two_step_path <- "Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur_2step.parquet"
if (file.exists(two_step_path)) {
  ref <- read_parquet(two_step_path)
  ref <- ref[ref$year < 2006 & ref$year > 1984, ]
  ref <- ref[ref$PWSID != "WV3303401", ]

  d2_4step <- step4[step4$downstream_step == 2, ]

  cat(sprintf("%-45s %8s %8s\n", "Metric", "2step.pq", "4step D2"))
  cat(strrep("-", 63), "\n")
  cat(sprintf("%-45s %8d %8d\n", "Unique PWSIDs",
              length(unique(ref$PWSID)), length(unique(d2_4step$PWSID))))
  cat(sprintf("%-45s %8d %8d\n", "PWSID x year rows",
              nrow(ref), nrow(d2_4step)))

  for (v in c("nitrates_MCL_share_days", "arsenic_MCL_share_days",
              "inorganic_chemicals_MCL_share_days", "radionuclides_MCL_share_days")) {
    n_ref   <- if (v %in% names(ref))    sum(ref[[v]]    > 0, na.rm = TRUE) else NA
    n_4step <- if (v %in% names(d2_4step)) sum(d2_4step[[v]] > 0, na.rm = TRUE) else NA
    cat(sprintf("%-45s %8s %8s\n", paste0("Rows with ", v, " > 0"),
                ifelse(is.na(n_ref), "missing", n_ref),
                ifelse(is.na(n_4step), "missing", n_4step)))
  }

  # PWSIDs only in one file
  only_ref   <- setdiff(unique(ref$PWSID), unique(d2_4step$PWSID))
  only_4step <- setdiff(unique(d2_4step$PWSID), unique(ref$PWSID))
  cat(sprintf("\nPWSIDs in 2step only:  %d\n", length(only_ref)))
  cat(sprintf("PWSIDs in 4step D2 only: %d\n", length(only_4step)))
  if (length(only_ref)   > 0) cat("  2step only:", paste(head(only_ref,   10), collapse = ", "), "\n")
  if (length(only_4step) > 0) cat("  4step only:", paste(head(only_4step, 10), collapse = ", "), "\n")
} else {
  warning("prod_vio_sulfur_2step.parquet not found - skipping comparison")
}
cat("==============================================\n\n")

# ── Helper: move notes below adjustbox (from run_main_tables.r) ───────────────
move_notes_below_adjustbox <- function(x) {
  x       <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj,
            paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                   trimws(note_block), "}"),
            x, fixed = TRUE)
  x
}

# ── Regression function (mirrors tsls_reg_output_main in run_main_tables.r) ───
tsls_reg_output_main <- function(dset, varlist, coalvar, regoutname, title, label,
                                  instr_str, dict = NULL, notes = NULL) {
  controls            <- c("num_facilities")
  drop_controls_exact <- paste0("^(", paste(controls, collapse = "|"), ")$")
  fe_str              <- "PWSID + STATE_CODE + year"
  controls_str        <- paste(controls, collapse = " + ")
  result              <- list()

  for (y in varlist) {
    dset_y <- dset[!is.na(dset[[y]]), ]
    cat("  Outcome:", y, "| n =", nrow(dset_y), "\n")
    f_ols <- as.formula(paste0(y, " ~ ", paste(coalvar, collapse = "+"),
                               " + ", controls_str, " | ", fe_str))
    f_rf  <- as.formula(paste0(y, " ~ ", instr_str,
                               " + ", controls_str, " | ", fe_str))
    f_iv  <- as.formula(paste0(y, " ~ ", controls_str,
                               " | ", fe_str,
                               " | ", paste(coalvar, collapse = "+"), " ~ ", instr_str))
    ols <- tryCatch(fixest::feols(f_ols, data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  OLS error:", conditionMessage(e), "\n"); NULL })
    rf  <- tryCatch(fixest::feols(f_rf,  data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  RF error:",  conditionMessage(e), "\n"); NULL })
    iv  <- tryCatch(fixest::feols(f_iv,  data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  IV error:",  conditionMessage(e), "\n"); NULL })
    if (!is.null(ols) && !is.null(rf) && !is.null(iv)) {
      result[[y]] <- list(OLS = ols, RF = rf, IV = iv)
    } else {
      cat("  Dropping", y, "- not all three models succeeded\n")
    }
  }

  if (length(result) == 0) {
    cat("  No estimable outcomes for", regoutname, "- skipping.\n")
    return(invisible(NULL))
  }

  model_list <- unlist(
    lapply(names(result),
           function(y) list(result[[y]]$OLS, result[[y]]$RF, result[[y]]$IV)),
    recursive = FALSE
  )
  etable_args <- c(
    model_list,
    list(
      fitstat         = ~ . + ivf1,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      drop            = drop_controls_exact,
      title           = title,
      label           = label,
      postprocess.tex = move_notes_below_adjustbox,
      file            = paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex")
    )
  )
  if (!is.null(dict))  etable_args$dict  <- dict
  if (!is.null(notes)) etable_args$notes <- notes
  do.call(etable, etable_args)
  rm(model_list, result)
  gc(verbose = FALSE)
  invisible(NULL)
}

# ── Outcome dictionaries and notes ────────────────────────────────────────────
vio_dict <- c(
  nitrates_MCL_share_days                  = "Nitrates (MCL)",
  arsenic_MCL_share_days                   = "Arsenic (MCL)",
  inorganic_chemicals_MCL_share_days       = "Inorg. chemicals (MCL)",
  radionuclides_MCL_share_days             = "Radionuclides (MCL)",
  total_coliform_MCL_share_days            = "Total coliform (MCL)",
  surface_ground_water_rule_MCL_share_days = "S/G water rule (MCL)",
  voc_MCL_share_days                       = "VOCs (MCL)",
  soc_MCL_share_days                       = "SOCs (MCL)",
  mining_health_MCL_share_days             = "Mining viol. composite (MCL)",
  mining_health_based_share_days           = "Mining viol. composite (health-based)"
)

std_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is days out of the year in violation (MCL only). ",
  "Instrument is post95 interacted with mean coal sulfur content of the intake watershed ",
  "(post95 x sulfur unified). ",
  "All regressions include PWSID, year, and state fixed effects. ",
  "Standard errors clustered at PWSID level. ",
  "Sample period 1985--2005."
)
nonmine_note <- paste0(
  std_note,
  " The number of observations differs across columns because some non-mining violation rules ",
  "(total coliform, surface/groundwater rule, VOCs, SOCs) were implemented during the sample period; ",
  "years prior to each rule's implementation are coded as missing and excluded from the regression."
)

mine_vars    <- c("nitrates_MCL_share_days", "arsenic_MCL_share_days",
                  "inorganic_chemicals_MCL_share_days", "radionuclides_MCL_share_days")
nonmine_vars <- c("total_coliform_MCL_share_days", "surface_ground_water_rule_MCL_share_days",
                  "voc_MCL_share_days", "soc_MCL_share_days")

mcl_composite_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is the sum of MCL-only violation days across nitrates, arsenic, ",
  "inorganic chemicals, and radionuclides. ",
  "Instrument is post95 interacted with mean coal sulfur content of the intake watershed ",
  "(post95 x sulfur unified). ",
  "All regressions include PWSID, year, and state fixed effects. ",
  "Standard errors clustered at PWSID level. ",
  "Sample period 1985--2005."
)

health_based_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is the sum of health-based violation days (EPA IS_HEALTH_BASED_IND flag) ",
  "across nitrates, arsenic, inorganic chemicals, and radionuclides. ",
  "Health-based violations include MCL, TT, and health-categorized MR violations. ",
  "Instrument is post95 interacted with mean coal sulfur content of the intake watershed ",
  "(post95 x sulfur unified). ",
  "All regressions include PWSID, year, and state fixed effects. ",
  "Standard errors clustered at PWSID level. ",
  "Sample period 1985--2005."
)

# ── Progressive samples and regression loop ───────────────────────────────────
sample_defs <- list(
  list(max_step = 1, tag = "d1",    title_samp = "D1 only (1 step downstream)"),
  list(max_step = 2, tag = "d1_d2", title_samp = "D1--D2 (1--2 steps downstream)"),
  list(max_step = 3, tag = "d1_d3", title_samp = "D1--D3 (1--3 steps downstream)"),
  list(max_step = 4, tag = "d1_d4", title_samp = "D1--D4 (1--4 steps downstream)")
)

summary_rows <- list()

for (sp in sample_defs) {
  dset <- step4[step4$downstream_step <= sp$max_step, ]
  n_cws  <- length(unique(dset$PWSID))
  n_rows <- nrow(dset)
  n_mcl_mine <- sum(sapply(mine_vars, function(v)
    if (v %in% names(dset)) sum(dset[[v]] > 0, na.rm = TRUE) else 0))
  n_mcl_nonmine <- sum(sapply(nonmine_vars, function(v)
    if (v %in% names(dset)) sum(dset[[v]] > 0, na.rm = TRUE) else 0))

  summary_rows[[sp$tag]] <- c(
    sample       = sp$title_samp,
    CWSs         = n_cws,
    pwsid_x_year = n_rows,
    mcl_mine_vio = n_mcl_mine,
    mcl_nonmine  = n_mcl_nonmine
  )

  cat("\n----------------------------------------------\n")
  cat("Sample:", sp$title_samp, "\n")
  cat("  CWSs:", n_cws, " | rows:", n_rows, "\n")
  cat("  Mining MCL vio rows:", n_mcl_mine,
      " | Non-mining MCL vio rows:", n_mcl_nonmine, "\n")

  # Mining violations (MCL)
  fname_mine <- paste0("2sls_4step_", sp$tag, "_minevio_mcl")
  cat("\nRunning:", fname_mine, "\n")
  tsls_reg_output_main(
    dset      = dset,
    varlist   = mine_vars,
    coalvar   = "num_coal_mines_upstream",
    regoutname = fname_mine,
    title     = paste0("Effect of coal mines on mining violations (MCL, ", sp$title_samp, ")"),
    label     = fname_mine,
    instr_str = "post95:sulfur_unified",
    dict      = vio_dict,
    notes     = std_note
  )

  # Non-mining violations (MCL)
  fname_nonmine <- paste0("2sls_4step_", sp$tag, "_nonminevio_mcl")
  cat("\nRunning:", fname_nonmine, "\n")
  tsls_reg_output_main(
    dset      = dset,
    varlist   = nonmine_vars,
    coalvar   = "num_coal_mines_upstream",
    regoutname = fname_nonmine,
    title     = paste0("Effect of coal mines on non-mining violations (MCL, ", sp$title_samp, ")"),
    label     = fname_nonmine,
    instr_str = "post95:sulfur_unified",
    dict      = vio_dict,
    notes     = nonmine_note
  )

  # MCL composite
  fname_mcl_comp <- paste0("2sls_4step_", sp$tag, "_mining_mcl_composite")
  cat("\nRunning:", fname_mcl_comp, "\n")
  tsls_reg_output_main(
    dset      = dset,
    varlist   = "mining_health_MCL_share_days",
    coalvar   = "num_coal_mines_upstream",
    regoutname = fname_mcl_comp,
    title     = paste0("Effect of coal mines on mining MCL composite (", sp$title_samp, ")"),
    label     = fname_mcl_comp,
    instr_str = "post95:sulfur_unified",
    dict      = vio_dict,
    notes     = mcl_composite_note
  )

  # Health-based composite
  fname_hb <- paste0("2sls_4step_", sp$tag, "_mining_healthbased")
  cat("\nRunning:", fname_hb, "\n")
  tsls_reg_output_main(
    dset      = dset,
    varlist   = "mining_health_based_share_days",
    coalvar   = "num_coal_mines_upstream",
    regoutname = fname_hb,
    title     = paste0("Effect of coal mines on mining health-based composite (", sp$title_samp, ")"),
    label     = fname_hb,
    instr_str = "post95:sulfur_unified",
    dict      = vio_dict,
    notes     = health_based_note
  )
}

# ── Print summary table ───────────────────────────────────────────────────────
cat("\n\n========== Sample expansion summary ==========\n")
cat(sprintf("%-35s %6s %12s %12s %12s\n",
            "Sample", "CWSs", "PWSID x yr", "MCL mine", "MCL non-mine"))
cat(strrep("-", 80), "\n")
for (tag in names(summary_rows)) {
  r <- summary_rows[[tag]]
  cat(sprintf("%-35s %6s %12s %12s %12s\n",
              r["sample"], r["CWSs"], r["pwsid_x_year"],
              r["mcl_mine_vio"], r["mcl_nonmine"]))
}
cat("==============================================\n")
cat("\nDone. Tables written to output/reg/2sls_4step_*.tex\n")
cat("  Mining MCL composite:    2sls_4step_d{N}_mining_mcl_composite.tex\n")
cat("  Mining health-based:     2sls_4step_d{N}_mining_healthbased.tex\n")
