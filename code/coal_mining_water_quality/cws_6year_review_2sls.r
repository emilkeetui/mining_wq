# ============================================================
# Script: cws_6year_review_2sls.r
# Purpose: Two-approach regression tables for coal mining effects
#          on measured chemical concentrations (EPA 6-Year Review).
#
#   Approach A — OLS with PWSID + year FEs (1998-2005).
#     Within-PWSID identification. No causal claim; shows
#     conditional correlation of coal exposure with concentration.
#
#   Approach B — Cross-sectional 2SLS with STATE_CODE + year FEs.
#     Instrument: sulfur_unified_sum (geological cross-section).
#     Identifies via within-state variation in watershed sulfur
#     content. Exclusion restriction: sulfur affects concentration
#     only through coal mining (may be violated by natural sulfur
#     in bedrock — note this caveat).
#
# Inputs:  clean_data/cws_6year_review.parquet
# Outputs: output/reg/2sls_6yr_dwnstrm_<chem>_<stat>.tex
# Author: EK  Date: 2026-05-26
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)

PROJECT_ROOT <- "Z:/ek559/mining_wq"
SIX_YR_PATH  <- file.path(PROJECT_ROOT, "clean_data", "cws_6year_review.parquet")
OUTPUT_DIR   <- file.path(PROJECT_ROOT, "output", "reg")

COALVAR   <- "num_coal_mines_upstream_sum"
CONTROLS  <- "num_facilities"
FE_PWSID  <- "PWSID + year"
FE_STATE  <- "STATE_CODE + year"
INSTR_CS  <- "sulfur_unified_sum"   # cross-sectional instrument for approach B

# ---------------------------------------------------------------------------
# Load 6-Year Review data
# ---------------------------------------------------------------------------
cat("Reading:", SIX_YR_PATH, "\n")
df6 <- read_parquet(SIX_YR_PATH)
cat("Loaded:", nrow(df6), "rows x", ncol(df6), "columns\n")
cat("Year range:", min(df6$year, na.rm = TRUE), "-", max(df6$year, na.rm = TRUE), "\n")
cat("Chemicals:", paste(sort(unique(df6$CHEMID_name)), collapse = ", "), "\n\n")

df6 <- df6[df6$year >= 1985 & df6$year <= 2005, ]
df6 <- df6[df6$PWSID != "WV3303401", ]

# Downstream-only sample
df6_dwnstrm <- df6[df6$minehuc_downstream_of_mine == 1 & df6$minehuc_mine == 0, ]
cat("Downstream rows:", nrow(df6_dwnstrm), "\n\n")

# ---------------------------------------------------------------------------
# LaTeX helpers (from run_main_tables.r)
# ---------------------------------------------------------------------------
move_notes_below_adjustbox <- function(x) {
  x <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj, paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                            trimws(note_block), "}"), x, fixed = TRUE)
  x
}

# Two columns per outcome: OLS | 2SLS(CS)
rename_cols_ols_cs2sls <- function(x) {
  x     <- paste(x, collapse = "\n")
  lines <- strsplit(x, "\n")[[1]]
  for (i in seq_along(lines)) {
    nums <- regmatches(lines[i], gregexpr("\\(\\d+\\)", lines[i]))[[1]]
    if (length(nums) >= 2) {
      num_vals <- as.integer(gsub("[()]", "", nums))
      if (identical(num_vals, seq_along(num_vals))) {
        labels <- rep(c("OLS", "2SLS (CS)"), length.out = length(nums))
        line   <- lines[i]
        for (j in seq_along(nums)) line <- sub(nums[j], labels[j], line, fixed = TRUE)
        lines[i] <- line
      }
    }
  }
  paste(lines, collapse = "\n")
}

postprocess_table <- function(x) rename_cols_ols_cs2sls(move_notes_below_adjustbox(x))

# ---------------------------------------------------------------------------
# Core table function: approach A (OLS) + approach B (cross-sectional 2SLS)
# per chemical outcome.
# ---------------------------------------------------------------------------
run_6yr_table <- function(dset, chem_name, out_col, regoutname,
                           title, label, dict = NULL, notes = NULL) {

  dset_y <- dset[!is.na(dset[[out_col]]), ]
  cat("  Chemical:", chem_name, "| n (non-missing VALUE):", nrow(dset_y), "\n")
  if (nrow(dset_y) < 30) { cat("  Too few obs — skipping.\n"); return(invisible(NULL)) }

  # Approach A: OLS, PWSID + year FEs
  f_ols <- as.formula(paste0(
    out_col, " ~ ", COALVAR, " + ", CONTROLS, " | ", FE_PWSID
  ))
  # Approach B: cross-sectional 2SLS, STATE_CODE + year FEs, sulfur instrument
  f_cs2sls <- as.formula(paste0(
    out_col, " ~ ", CONTROLS, " | ", FE_STATE,
    " | ", COALVAR, " ~ ", INSTR_CS
  ))

  ols    <- tryCatch(fixest::feols(f_ols,    data = dset_y, cluster = ~PWSID),
                     error = function(e) { cat("  OLS error:", conditionMessage(e), "\n"); NULL })
  cs2sls <- tryCatch(fixest::feols(f_cs2sls, data = dset_y, cluster = ~PWSID),
                     error = function(e) { cat("  CS-2SLS error:", conditionMessage(e), "\n"); NULL })

  # Clustered first-stage F-stat for approach B
  f_stat_b <- NA_real_
  if (!is.null(cs2sls)) {
    f_fs_b <- as.formula(paste0(
      COALVAR, " ~ ", INSTR_CS, " + ", CONTROLS, " | ", FE_STATE
    ))
    fs_b <- tryCatch(fixest::feols(f_fs_b, data = dset_y, cluster = ~PWSID), error = function(e) NULL)
    if (!is.null(fs_b)) {
      t_b     <- coef(fs_b)[INSTR_CS] / se(fs_b)[INSTR_CS]
      f_stat_b <- round(t_b^2, 2)
      cat("  First-stage F (CS, clustered):", f_stat_b, "\n")
    }
  }

  if (is.null(ols) && is.null(cs2sls)) {
    cat("  Both models failed — skipping.\n"); return(invisible(NULL))
  }

  model_list <- Filter(Negate(is.null), list(ols, cs2sls))

  f_label <- paste0("F-test (1st stage, CS, clustered), ", COALVAR)
  f_vec   <- c(
    if (!is.null(ols))    "" else NULL,
    if (!is.null(cs2sls)) ifelse(is.na(f_stat_b), "", format(round(f_stat_b, 2), nsmall = 2)) else NULL
  )
  el        <- list(f_vec)
  names(el) <- f_label

  out_path    <- file.path(OUTPUT_DIR, paste0(regoutname, ".tex"))
  etable_args <- c(
    model_list,
    list(
      fitstat         = ~ .,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      drop            = "^num_facilities$",
      title           = title,
      label           = label,
      postprocess.tex = postprocess_table,
      extralines      = el,
      file            = out_path
    )
  )
  if (!is.null(dict))  etable_args$dict  <- dict
  if (!is.null(notes)) etable_args$notes <- notes
  do.call(etable, etable_args)
  cat("  Written:", out_path, "\n")
}

# ---------------------------------------------------------------------------
# Table notes
# ---------------------------------------------------------------------------
note_6yr <- paste0(
  "OLS column includes PWSID and year fixed effects. ",
  "2SLS (CS) column replaces PWSID FEs with STATE\\_CODE + year FEs and instruments ",
  "num\\_coal\\_mines\\_upstream\\_sum with sulfur\\_unified\\_sum (watershed sulfur content, ",
  "cross-sectional). ",
  "Identification in 2SLS (CS) relies on within-state variation in watershed sulfur ",
  "content; the exclusion restriction may be violated if natural (non-mining) sulfur ",
  "in bedrock independently affects water chemistry. ",
  "Dependent variable is the mean measured concentration across all samples for a ",
  "given CWS and year from the EPA 6-Year Review (1998--2005). ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine. ",
  "Standard errors clustered at PWSID level. ",
  "Rows with no 6-Year Review observation for the relevant chemical are excluded."
)

# ---------------------------------------------------------------------------
# Chemical specs — proof of concept: mean arsenic and mean nitrate
# ---------------------------------------------------------------------------
chem_specs <- list(
  list(chem = "arsenic", outvar = "VALUE", stat = "mean", units = "\\textmu g/L"),
  list(chem = "nitrate",  outvar = "VALUE", stat = "mean", units = "mg/L")
)

# ---------------------------------------------------------------------------
# Run tables
# ---------------------------------------------------------------------------
for (cs in chem_specs) {
  chem_data <- df6_dwnstrm[df6_dwnstrm$CHEMID_name == cs$chem, ]
  cat("\nChemical:", cs$chem, "| downstream rows:", nrow(chem_data), "\n")

  out_col              <- paste0(cs$stat, "_", gsub("[^a-zA-Z0-9]", "_", cs$chem))
  chem_data[[out_col]] <- chem_data[[cs$outvar]]

  dict_chem <- c(
    setNames(paste0("Mean ", cs$chem, " conc. (", cs$units, ")"), out_col),
    setNames("Coal mines (upstream)", COALVAR)
  )

  fname <- paste0("6yr_dwnstrm_", gsub(" ", "_", cs$chem), "_", cs$stat)
  title <- paste0(
    "Effect of coal mines on measured ", cs$chem, " concentration (",
    cs$stat, ", CWSs at most one HUC12 downstream)"
  )

  run_6yr_table(
    dset       = chem_data,
    chem_name  = cs$chem,
    out_col    = out_col,
    regoutname = fname,
    title      = title,
    label      = paste0("tab:", fname),
    dict       = dict_chem,
    notes      = note_6yr
  )
}

cat("\nDone.\n")
