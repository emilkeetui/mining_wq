# ============================================================
# Script: run_4step_norad_composite.r
# Purpose: Run MCL composite (excluding radionuclides) 2SLS on the 4-step
#          downstream sample for all progressive sample cuts (D1 through D1-D4).
#          Addresses radionuclide geology confound identified in diagnostics:
#          radionuclides RF is positive in both main and downstream samples,
#          consistent with post-1995 federal rule tightening + geology correlation
#          rather than a mining channel.
# Inputs:  clean_data/cws_data/prod_vio_sulfur_4step.parquet
# Outputs: output/reg/2sls_4step_d{N}_mining_mcl_norad.tex  (N = 1, d1_d2, d1_d3, d1_d4)
# Author: EK  Date: 2026-04-27
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)

ROOT <- "Z:/ek559/mining_wq"

step4 <- read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur_4step.parquet"))
step4 <- step4[step4$year < 2006 & step4$year > 1984, ]
step4 <- step4[step4$PWSID != "WV3303401", ]

# MCL composite excluding radionuclides
step4$mining_mcl_norad_share_days <- (
  step4$nitrates_MCL_share_days +
  step4$arsenic_MCL_share_days +
  step4$inorganic_chemicals_MCL_share_days
)

cat("Rows:", nrow(step4), "\n")
cat("MCL norad composite > 0:", sum(step4$mining_mcl_norad_share_days > 0, na.rm = TRUE), "\n")

# ── Helpers ───────────────────────────────────────────────────────────────────
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

vio_dict <- c(
  mining_mcl_norad_share_days = "Mining MCL composite (excl. radionuclides)"
)

fe_str       <- "PWSID + STATE_CODE + year"
controls_str <- "num_facilities"
instr_str    <- "post95:sulfur_unified"
coalvar      <- "num_coal_mines_upstream"

norad_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is the sum of MCL-only violation days across nitrates, arsenic, ",
  "and inorganic chemicals (radionuclides excluded). ",
  "Radionuclides are excluded because the reduced form is positive in both the main colocated ",
  "sample and the downstream sample, consistent with a geology confound: high-sulfur geology ",
  "correlates with natural radionuclide presence, and post-1995 EPA radionuclide rule tightening ",
  "increased detection of violations independently of mine activity. ",
  "Instrument is post95 interacted with mean coal sulfur content of the intake watershed ",
  "(post95 x sulfur unified). ",
  "All regressions include PWSID, year, and state fixed effects. ",
  "Standard errors clustered at PWSID level. ",
  "Sample period 1985--2005."
)

run_one <- function(dset, tag, title_samp) {
  regoutname <- paste0("2sls_4step_", tag, "_mining_mcl_norad")
  cat("\n--- Sample:", title_samp, "| rows:", nrow(dset), "---\n")
  cat("  norad composite > 0:", sum(dset$mining_mcl_norad_share_days > 0, na.rm = TRUE), "\n")

  dset_y <- dset[!is.na(dset$mining_mcl_norad_share_days), ]
  f_ols  <- as.formula(paste0("mining_mcl_norad_share_days ~ ", coalvar, " + ",
                               controls_str, " | ", fe_str))
  f_rf   <- as.formula(paste0("mining_mcl_norad_share_days ~ ", instr_str,
                               " + ", controls_str, " | ", fe_str))
  f_iv   <- as.formula(paste0("mining_mcl_norad_share_days ~ ", controls_str,
                               " | ", fe_str, " | ", coalvar, " ~ ", instr_str))

  ols <- tryCatch(feols(f_ols, data = dset_y, cluster = ~ PWSID),
                  error = function(e) { cat("  OLS error:", conditionMessage(e), "\n"); NULL })
  rf  <- tryCatch(feols(f_rf,  data = dset_y, cluster = ~ PWSID),
                  error = function(e) { cat("  RF error:",  conditionMessage(e), "\n"); NULL })
  iv  <- tryCatch(feols(f_iv,  data = dset_y, cluster = ~ PWSID),
                  error = function(e) { cat("  IV error:",  conditionMessage(e), "\n"); NULL })

  if (is.null(ols) || is.null(rf) || is.null(iv)) {
    cat("  Skipping", regoutname, "\n"); return(invisible(NULL))
  }

  cat("  OLS:", round(coef(ols)[coalvar], 4),
      "| RF:", round(coef(rf)[instr_str], 4),
      "| 2SLS:", round(coef(iv)[coalvar], 4), "\n")

  etable(
    ols, rf, iv,
    fitstat         = ~ . + ivf1,
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    dict            = vio_dict,
    title           = paste0("Effect of coal mines on mining MCL composite, excl. radionuclides (",
                              title_samp, ")"),
    label           = regoutname,
    notes           = norad_note,
    postprocess.tex = move_notes_below_adjustbox,
    file            = file.path(ROOT, "output/reg", paste0(regoutname, ".tex"))
  )
  rm(ols, rf, iv); gc(verbose = FALSE)
  invisible(NULL)
}

sample_defs <- list(
  list(max_step = 1, tag = "d1",    title_samp = "D1 only"),
  list(max_step = 2, tag = "d1_d2", title_samp = "D1--D2"),
  list(max_step = 3, tag = "d1_d3", title_samp = "D1--D3"),
  list(max_step = 4, tag = "d1_d4", title_samp = "D1--D4")
)

for (sp in sample_defs) {
  dset <- step4[step4$downstream_step <= sp$max_step, ]
  run_one(dset, sp$tag, sp$title_samp)
}

cat("\nDone. Written to output/reg/2sls_4step_d*_mining_mcl_norad.tex\n")
