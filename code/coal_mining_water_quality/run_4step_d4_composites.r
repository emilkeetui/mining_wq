# ============================================================
# Script: run_4step_d4_composites.r
# Purpose: Run MCL composite and health-based composite 2SLS on the full
#          D1–D4 sample. Separate script to avoid memory exhaustion that
#          occurs when running all 4-step tables in a single R session.
# Inputs:  clean_data/cws_data/prod_vio_sulfur_4step.parquet
# Outputs: output/reg/2sls_4step_d1_d4_mining_mcl_composite.tex
#          output/reg/2sls_4step_d1_d4_mining_healthbased.tex
# Author: EK  Date: 2026-04-27
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)

step4 <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur_4step.parquet")
step4 <- step4[step4$year < 2006 & step4$year > 1984, ]
step4 <- step4[step4$PWSID != "WV3303401", ]

step4$mining_health_MCL_share_days <- (
  step4$nitrates_MCL_share_days +
  step4$arsenic_MCL_share_days +
  step4$inorganic_chemicals_MCL_share_days +
  step4$radionuclides_MCL_share_days
)
step4$mining_health_based_share_days <- (
  step4$nitrates_health_share_days +
  step4$arsenic_health_share_days +
  step4$inorganic_chemicals_health_share_days +
  step4$radionuclides_health_share_days
)

cat("D1-D4 rows:", nrow(step4), "| MCL composite > 0:",
    sum(step4$mining_health_MCL_share_days > 0, na.rm=TRUE),
    "| Health-based > 0:",
    sum(step4$mining_health_based_share_days > 0, na.rm=TRUE), "\n")

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
  mining_health_MCL_share_days   = "Mining viol. composite (MCL)",
  mining_health_based_share_days = "Mining viol. composite (health-based)"
)

fe_str       <- "PWSID + STATE_CODE + year"
controls_str <- "num_facilities"
instr_str    <- "post95:sulfur_unified"
coalvar      <- "num_coal_mines_upstream"

run_one <- function(outcome, regoutname, title, notes) {
  dset <- step4[!is.na(step4[[outcome]]), ]
  cat("Outcome:", outcome, "| n =", nrow(dset), "\n")
  f_ols <- as.formula(paste0(outcome, " ~ ", coalvar, " + ", controls_str, " | ", fe_str))
  f_rf  <- as.formula(paste0(outcome, " ~ ", instr_str, " + ", controls_str, " | ", fe_str))
  f_iv  <- as.formula(paste0(outcome, " ~ ", controls_str, " | ", fe_str,
                              " | ", coalvar, " ~ ", instr_str))
  ols <- tryCatch(feols(f_ols, data=dset, cluster=~PWSID),
                  error = function(e) { cat("OLS error:", conditionMessage(e), "\n"); NULL })
  rf  <- tryCatch(feols(f_rf,  data=dset, cluster=~PWSID),
                  error = function(e) { cat("RF error:",  conditionMessage(e), "\n"); NULL })
  iv  <- tryCatch(feols(f_iv,  data=dset, cluster=~PWSID),
                  error = function(e) { cat("IV error:",  conditionMessage(e), "\n"); NULL })
  if (is.null(ols) || is.null(rf) || is.null(iv)) {
    cat("Skipping", regoutname, "\n"); return(invisible(NULL))
  }
  etable(
    ols, rf, iv,
    fitstat         = ~ . + ivf1,
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    dict            = vio_dict,
    title           = title,
    label           = regoutname,
    notes           = notes,
    postprocess.tex = move_notes_below_adjustbox,
    file            = paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex")
  )
  rm(ols, rf, iv); gc(verbose = FALSE)
  invisible(NULL)
}

mcl_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is the sum of MCL-only violation days across nitrates, arsenic, ",
  "inorganic chemicals, and radionuclides. ",
  "Instrument is post95 interacted with mean coal sulfur content of the intake watershed ",
  "(post95 x sulfur unified). ",
  "All regressions include PWSID, year, and state fixed effects. ",
  "Standard errors clustered at PWSID level. ",
  "Sample period 1985--2005."
)

hb_note <- paste0(
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

run_one(
  outcome    = "mining_health_MCL_share_days",
  regoutname = "2sls_4step_d1_d4_mining_mcl_composite",
  title      = "Effect of coal mines on mining MCL composite (D1--D4, 1--4 steps downstream)",
  notes      = mcl_note
)

run_one(
  outcome    = "mining_health_based_share_days",
  regoutname = "2sls_4step_d1_d4_mining_healthbased",
  title      = "Effect of coal mines on mining health-based composite (D1--D4, 1--4 steps downstream)",
  notes      = hb_note
)

cat("\nDone. Written:\n")
cat("  output/reg/2sls_4step_d1_d4_mining_mcl_composite.tex\n")
cat("  output/reg/2sls_4step_d1_d4_mining_healthbased.tex\n")
