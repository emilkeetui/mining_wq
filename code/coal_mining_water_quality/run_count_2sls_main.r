# ============================================================
# Script: run_count_2sls_main.r
# Purpose: Poisson control-function 2SLS on days-in-violation
#          counts, mirroring the main table sample cuts in
#          run_main_tables.r. Addresses the publication-readiness
#          assessment problems: (1) non-linear count DGP, (2)
#          weak first stage in colocated sample, (3) MCL power.
#          Covers all four standard sample cuts plus the 4-step
#          downstream sample where the instrument is strongest.
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur.parquet
#   clean_data/cws_data/prod_vio_sulfur_4step.parquet
# Outputs:
#   output/reg/poisson_cf_colocated.tex
#   output/reg/poisson_cf_downstream.tex
#   output/reg/poisson_cf_coloc_down.tex
#   output/reg/poisson_cf_4step.tex
# Author: EK  Date: 2026-04-28
# ============================================================
#
# METHOD — Poisson Control Function (CF) 2SLS
# ─────────────────────────────────────────────────────────────
# Wooldridge (2002, 2010): for a non-linear second stage, add
# first-stage OLS residuals (v_hat) as a regressor. The Poisson
# QMLE coefficient on the endogenous variable is then consistent.
# Coefficient interpretation: log incidence rate ratio (log IRR).
# exp(coef) = multiplicative effect on expected violation days.
# Test of endogeneity: t-test on v_hat coefficient.
#
# Each sample cut uses its own treatment variable and instrument:
#   Colocated sample : treat = num_coal_mines_colocated
#                      instr = post95 × sulfur_colocated
#   Downstream / combined / 4-step:
#                      treat = num_coal_mines_upstream (or unified)
#                      instr = post95 × sulfur_upstream (or unified)
#
# Poisson FE QMLE is incidental-parameter-bias-free (Hausman et al.
# 1984). SE clustered at PWSID. Outcomes too sparse for NB here
# (addressed in run_count_2sls.r for the better-powered 4-step sample).

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(dplyr)

ROOT   <- "Z:/ek559/mining_wq"
OUTREG <- file.path(ROOT, "output/reg")
YEARS  <- 1985:2005
OUTLIER <- "WV3303401"

# ── 1. Load data ──────────────────────────────────────────────────────────────
cat("Loading main dataset...\n")
main <- read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"))
main <- main[main$year >= min(YEARS) & main$year <= max(YEARS) &
               main$PWSID != OUTLIER, ]
stopifnot(is.character(main$PWSID))

cat("Loading 4-step downstream dataset...\n")
step4 <- read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur_4step.parquet"))
step4 <- step4[step4$year >= min(YEARS) & step4$year <= max(YEARS) &
                 step4$PWSID != OUTLIER &
                 step4$minehuc_downstream_of_mine_4step == 1, ]
stopifnot(is.character(step4$PWSID))

# ── 2. Sample cuts ────────────────────────────────────────────────────────────
samples <- list(
  colocated   = main[main$minehuc_mine == 1 &
                       main$minehuc_downstream_of_mine == 0, ],
  downstream  = main[main$minehuc_downstream_of_mine == 1 &
                       main$minehuc_mine == 0, ],
  coloc_down  = main[main$minehuc_upstream_of_mine == 0, ],
  step4       = step4
)

# Treatment variable and instrument per sample
specs <- list(
  colocated  = list(treat = "num_coal_mines_colocated",
                    instr = "post95:sulfur_colocated"),
  downstream = list(treat = "num_coal_mines_upstream",
                    instr = "post95:sulfur_upstream"),
  coloc_down = list(treat = "num_coal_mines_unified",
                    instr = "post95:sulfur_unified"),
  step4      = list(treat = "num_coal_mines_upstream",
                    instr = "post95:sulfur_upstream")
)

for (nm in names(samples)) {
  cat("  ", nm, ":", nrow(samples[[nm]]), "rows |",
      length(unique(samples[[nm]]$PWSID)), "PWSIDs\n")
}

# ── 3. Outcomes ───────────────────────────────────────────────────────────────
# Eight columns: 4 contaminants × (MR + MCL).  Round to integer days.
OUTCOMES <- c(
  "nitrates_MR_share_days",
  "nitrates_MCL_share_days",
  "arsenic_MR_share_days",
  "arsenic_MCL_share_days",
  "inorganic_chemicals_MR_share_days",
  "inorganic_chemicals_MCL_share_days",
  "radionuclides_MR_share_days",
  "radionuclides_MCL_share_days"
)
COL_LABELS <- c(
  "Nitrates MR",    "Nitrates MCL",
  "Arsenic MR",     "Arsenic MCL",
  "Inorganic MR",   "Inorganic MCL",
  "Radionuclides MR","Radionuclides MCL"
)

round_outcomes <- function(df) {
  for (v in OUTCOMES) if (v %in% names(df)) df[[v]] <- as.integer(round(df[[v]]))
  df
}
samples <- lapply(samples, round_outcomes)

# Print nonzero counts by sample
cat("\nNonzero violation-day counts:\n")
for (nm in names(samples)) {
  d <- samples[[nm]]
  cat(" ", nm, ":\n")
  for (v in OUTCOMES) {
    if (v %in% names(d))
      cat("    ", v, ":", sum(d[[v]] > 0, na.rm = TRUE), "\n")
  }
}

# ── 4. First-stage helper ─────────────────────────────────────────────────────
make_first_stage <- function(df, treat, instr, label) {
  fml_fs <- as.formula(paste0(treat, " ~ ", instr,
                              " + num_facilities | PWSID + year + STATE_CODE"))
  fs_vars <- c(treat, "num_facilities", "PWSID", "year", "STATE_CODE",
               gsub("post95:", "", instr),   # sulfur variable
               "post95")
  df_fs <- df[complete.cases(df[, intersect(fs_vars, names(df)), drop = FALSE]), ]
  mod <- feols(fml_fs, data = df_fs, cluster = ~PWSID, warn = FALSE, notes = FALSE)
  cat("\n--- First stage:", label, "---\n")
  cat("  N:", nobs(mod), "\n")
  tryCatch({
    w <- wald(mod, instr)
    cat("  Wald F (instrument):", round(w$stat, 2),
        " | p =", round(w$p, 4), "\n")
  }, error = function(e) cat("  Wald F unavailable\n"))
  ct <- coeftable(mod)
  print(ct[grep("post95|sulfur", rownames(ct)), , drop = FALSE])
  # Compute v_hat = actual - fitted for all df_fs rows.
  # predict(mod, newdata) uses estimated FEs, so it works for every row of
  # df_fs (which is a strict subset of the training data).  This avoids the
  # obs_selection / singleton-removal indexing problem entirely.
  df_fs$v_hat <- tryCatch(
    df_fs[[treat]] - predict(mod, newdata = df_fs),
    error = function(e) {
      cat("  predict() failed — falling back to residuals()\n")
      res <- residuals(mod)
      out <- rep(NA_real_, nrow(df_fs))
      out[seq_along(res)] <- res
      out
    }
  )
  df <- left_join(df, df_fs[, c("PWSID", "year", "v_hat")],
                  by = c("PWSID", "year"))
  list(data = df, mod = mod)
}

# Run first stages
cat("\n=== FIRST STAGES ===\n")
fs_results <- mapply(
  function(df, spec, nm) make_first_stage(df, spec$treat, spec$instr, nm),
  samples, specs, names(samples),
  SIMPLIFY = FALSE
)
samples <- lapply(fs_results, `[[`, "data")

# ── 5. Poisson CF helper ──────────────────────────────────────────────────────
MIN_NONZERO <- 10   # minimum nonzero obs to attempt Poisson

run_poisson_cf <- function(df, outcome, treat) {
  d <- df[!is.na(df[[outcome]]) & !is.na(df$v_hat), ]
  nz <- sum(d[[outcome]] > 0, na.rm = TRUE)
  if (nz < MIN_NONZERO) {
    cat("    skip", outcome, "(nonzero =", nz, "< 10)\n")
    return(NULL)
  }
  fml <- as.formula(paste0(
    outcome, " ~ ", treat, " + v_hat + num_facilities | PWSID + year + STATE_CODE"
  ))
  mod <- tryCatch(
    feglm(fml, data = d, family = "poisson", cluster = ~PWSID,
          warn = FALSE, notes = FALSE),
    error = function(e) {
      cat("    error:", conditionMessage(e), "\n")
      NULL
    }
  )
  # Guard against Poisson divergence (complete separation on sparse outcomes)
  if (!is.null(mod)) {
    max_coef <- max(abs(coef(mod)), na.rm = TRUE)
    if (max_coef > 30) {
      cat("    skip", outcome, "— Poisson diverged (max|coef|=",
          round(max_coef, 1), "; likely complete separation)\n")
      return(NULL)
    }
  }
  mod
}

# ── 6. Run Poisson CF on all sample cuts ──────────────────────────────────────
cat("\n=== POISSON CF 2SLS ===\n")
all_models <- list()
for (nm in names(samples)) {
  cat(" Sample:", nm, "\n")
  treat <- specs[[nm]]$treat
  mods <- lapply(OUTCOMES, function(v) run_poisson_cf(samples[[nm]], v, treat))
  names(mods) <- OUTCOMES
  all_models[[nm]] <- mods
}

# ── 7. Write LaTeX tables ─────────────────────────────────────────────────────
SAMPLE_TITLES <- c(
  colocated  = "Colocated (mine HUC)",
  downstream = "1-step downstream",
  coloc_down = "Colocated + downstream",
  step4      = "At-most-4-step downstream"
)
OUTFILES <- c(
  colocated  = "poisson_cf_colocated.tex",
  downstream = "poisson_cf_downstream.tex",
  coloc_down = "poisson_cf_coloc_down.tex",
  step4      = "poisson_cf_4step.tex"
)
INSTR_NOTES <- c(
  colocated  = "post-1995 $\\times$ colocated sulfur\\%",
  downstream = "post-1995 $\\times$ upstream sulfur\\%",
  coloc_down = "post-1995 $\\times$ unified sulfur\\%",
  step4      = "post-1995 $\\times$ upstream sulfur\\%"
)

dict <- c(
  "num_coal_mines_colocated" = "Coal mines (colocated)",
  "num_coal_mines_upstream"  = "Coal mines (upstream)",
  "num_coal_mines_unified"   = "Coal mines (unified)",
  "v_hat"                    = "CF residual",
  "num_facilities"           = "N facilities"
)

for (nm in names(all_models)) {
  mods <- Filter(Negate(is.null), all_models[[nm]])
  if (length(mods) == 0) {
    cat("  No models for", nm, "\n")
    next
  }
  labs <- COL_LABELS[match(names(mods), OUTCOMES)]
  outfile <- file.path(OUTREG, OUTFILES[[nm]])
  tryCatch({
    etable(
      mods,
      title   = paste0("Poisson CF 2SLS — ", SAMPLE_TITLES[[nm]]),
      headers = labs,
      keep    = c(paste0("%", specs[[nm]]$treat), "%v_hat"),
      dict    = dict,
      fitstat = ~ n,
      tex     = TRUE,
      file    = outfile,
      replace = TRUE,
      style.tex = style.tex("base"),
      notes   = paste0(
        "Poisson QMLE control-function 2SLS (Wooldridge 2002). ",
        "Instrument: ", INSTR_NOTES[[nm]], ". ",
        "Outcomes: integer days in violation per PWSID-year. ",
        "Coefficients are log incidence rate ratios; ",
        "exp(coef) = multiplicative effect on expected days. ",
        "``CF residual'' tests endogeneity (t-test on first-stage residual). ",
        "Fixed effects: PWSID, year, state. SE clustered at PWSID. ",
        "Sample: ", SAMPLE_TITLES[[nm]], ", 1985--2005."
      )
    )
    cat("  Saved:", outfile, "\n")
  }, error = function(e) cat("  etable error (", nm, "):", conditionMessage(e), "\n"))
}

# ── 8. Results summary ────────────────────────────────────────────────────────
cat("\n")
cat("=================================================================\n")
cat("POISSON CF 2SLS — RESULTS SUMMARY\n")
cat("=================================================================\n")
for (nm in names(all_models)) {
  cat("\nSample:", SAMPLE_TITLES[[nm]], "\n")
  for (v in OUTCOMES) {
    m <- all_models[[nm]][[v]]
    if (is.null(m)) { cat("  ", v, ": skipped\n"); next }
    ct <- coeftable(m)
    treat_row <- ct[rownames(ct) == specs[[nm]]$treat, , drop = FALSE]
    cf_row    <- ct[rownames(ct) == "v_hat", , drop = FALSE]
    if (nrow(treat_row) == 0) { cat("  ", v, ": coef row missing\n"); next }
    pv_col <- intersect(c("Pr(>|t|)", "Pr(>|z|)"), colnames(ct))[1]
    coef_val <- round(treat_row[1, "Estimate"], 3)
    p_val    <- round(treat_row[1, pv_col], 3)
    irr      <- round(exp(coef_val), 2)
    cf_p     <- if (nrow(cf_row) > 0) round(cf_row[1, pv_col], 3) else NA
    sig <- dplyr::case_when(p_val < 0.01 ~ "***", p_val < 0.05 ~ "**",
                            p_val < 0.10 ~ "*",   TRUE ~ "")
    cat(sprintf("  %-42s coef=%6.3f (IRR=%4.2f) p=%5.3f%s | CF-p=%5.3f\n",
                v, coef_val, irr, p_val, sig, cf_p))
  }
}
cat("\n=================================================================\n")
cat("KEY:\n")
cat("  coef = log IRR; exp(coef) = multiplicative effect on days in violation\n")
cat("  CF-p = p-value on first-stage residual (endogeneity test)\n")
cat("  *** p<0.01  ** p<0.05  * p<0.10\n")
cat("=================================================================\n")
cat("\nDone. Tables in output/reg/poisson_cf_*.tex\n")
