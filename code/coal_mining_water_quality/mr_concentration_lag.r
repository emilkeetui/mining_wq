# ============================================================
# Script: mr_concentration_lag.r
# Purpose: Test whether MR (monitoring/reporting) violations in a month
#          are predicted by the prior month's mean contaminant concentration
#          (regulator-pivot / strategic avoidance mechanism). Unit of
#          observation: CWS × month. Sample: downstream-only SYR2 CWSs,
#          1998-2005. Built from build_mr_concentration_lag_monthly.py.
#          Specs: (A) arsenic, (B) nitrate -- same-contaminant MR vio in
#          month; (C) pooled -- RULE_CODE==333.0 (IOC) MR vio in month.
#          IVs: 1-month lagged mean ratio and near_mcl. Months with no
#          contaminant reading in the prior month are excluded (lag = NA).
#          Placebo table uses 1-month lead instead of lag.
# Inputs:  clean_data/mr_concentration_lag_monthly.parquet
# Outputs: output/reg/mr_concentration_lag.tex
#          output/reg/mr_concentration_lag_placebo.tex
# Author: EK  Date: 2026-06-30
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(fixest)

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

# ── Step 1: Load + schema check ───────────────────────────────────────────────
cat("Loading CWS-month panel...\n")
df <- read_parquet("clean_data/mr_concentration_lag_monthly.parquet")
str(df)   # PWSID must be <chr>, YEAR must be <int>

cat(sprintf("\nRows: %d | unique PWSID: %d | years %d-%d\n",
            nrow(df), length(unique(df$PWSID)), min(df$YEAR), max(df$YEAR)))
cat(sprintf("ratio_lag1 non-NA: %d (months with a prior-month reading)\n",
            sum(!is.na(df$ratio_lag1))))
cat(sprintf("mr_same_month mean: %.4f\n", mean(df$mr_same_month)))
cat(sprintf("mr_ioc_month mean:  %.4f\n", mean(df$mr_ioc_month)))

ars_df  <- df[df$contaminant_code == "1005", ]
nit_df  <- df[df$contaminant_code == "1040", ]
pool_df <- df

cat(sprintf("\nArsenic (1005) subset N = %d\n", nrow(ars_df)))
cat(sprintf("Nitrate (1040) subset N = %d\n", nrow(nit_df)))
cat(sprintf("Pooled subset N = %d\n", nrow(pool_df)))

# ── Step 2: Named formulas ────────────────────────────────────────────────────
# Main: DV = binary MR violation in month; IVs = 1-month lagged ratio/near_mcl.
# Observations where lag is NA (no reading in prior month) are dropped by feols.
fml_ars  <- mr_same_month  ~ ratio_lag1 + near_mcl_lag1 | PWSID + YEAR
fml_nit  <- mr_same_month  ~ ratio_lag1 + near_mcl_lag1 | PWSID + YEAR
fml_pool <- mr_ioc_month   ~ ratio_lag1 + near_mcl_lag1 | PWSID + YEAR + contaminant_code

# Placebo: use 1-month lead of ratio/near_mcl (future readings should not predict
# current violations if the causal direction is concentration → avoidance).
fml_ars_placebo  <- mr_same_month ~ ratio_lead1 + near_mcl_lead1 | PWSID + YEAR
fml_nit_placebo  <- mr_same_month ~ ratio_lead1 + near_mcl_lead1 | PWSID + YEAR
fml_pool_placebo <- mr_ioc_month  ~ ratio_lead1 + near_mcl_lead1 | PWSID + YEAR + contaminant_code

have_ars <- nrow(ars_df) > 0
if (!have_ars) {
  cat("\n[NOTE] Arsenic subset is empty (N=0) -- arsenic column omitted from both tables.\n")
}

# ── Step 3: Main regressions (lagged covariates) ──────────────────────────────
nit  <- feols(fml_nit,  data = nit_df,  cluster = ~PWSID)
pool <- feols(fml_pool, data = pool_df, cluster = ~PWSID)

cat("\n--- (B) Nitrate, lagged spec ---\n");  print(summary(nit))
cat("\n--- (C) Pooled any-IOC, lagged spec ---\n"); print(summary(pool))

if (have_ars) {
  ars <- feols(fml_ars, data = ars_df, cluster = ~PWSID)
  cat("\n--- (A) Arsenic, lagged spec ---\n"); print(summary(ars))
}

# ── Step 4: Placebo regressions (lead covariates) ─────────────────────────────
nit_p  <- feols(fml_nit_placebo,  data = nit_df,  cluster = ~PWSID)
pool_p <- feols(fml_pool_placebo, data = pool_df, cluster = ~PWSID)

cat("\n--- (B) Nitrate, lead placebo ---\n");  print(summary(nit_p))
cat("\n--- (C) Pooled any-IOC, lead placebo ---\n"); print(summary(pool_p))

have_ars_placebo <- FALSE
if (have_ars) {
  ars_p <- tryCatch(
    feols(fml_ars_placebo, data = ars_df, cluster = ~PWSID),
    error = function(e) {
      cat(sprintf("\n[NOTE] Arsenic lead-placebo skipped: %s\n", e$message))
      NULL
    }
  )
  have_ars_placebo <- !is.null(ars_p)
  if (have_ars_placebo) {
    cat("\n--- (A) Arsenic, lead placebo ---\n"); print(summary(ars_p))
  }
}

# ── Step 5: LaTeX tables ──────────────────────────────────────────────────────
# move_notes_below_adjustbox() — copied from enforcement_chain_d12.r:476. Without
# this, style.tex("aer", adjustbox = TRUE) leaves the notes line inside the
# adjustbox, where they get compressed onto a single line alongside the table
# instead of wrapping below it.
move_notes_below_adjustbox <- function(x) {
  x           <- paste(x, collapse = "\n")
  end_adj     <- "\\end{adjustbox}"
  par_rag     <- "\\par \\raggedright"
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

dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

out_tex <- file.path(ROOT, "output/reg/mr_concentration_lag.tex")
ars_clause <- if (have_ars) "" else " Arsenic column omitted (no observations survive)."
note_main <- paste0(
  "Downstream-only mining sample (minehuc_downstream_of_mine==1 & minehuc_mine==0), ",
  "SYR2 only (1998-2005). Unit of observation: CWS (PWSID) × calendar month. ",
  "Outcome: binary = 1 if any MR violation occurred in that month ",
  "(same-contaminant MR violation for Arsenic/Nitrate; RULE_CODE==333.0 MR violation ",
  "for Pooled). Independent variables: mean ratio and near_mcl from the prior calendar ",
  "month (1-month lag). Observations where no contaminant reading was taken in the prior ",
  "month are excluded (lag = missing; not coded as zero). ",
  "Pooled any-IOC: MR violation under RULE_CODE==333.0 (Inorganic Chemicals / Other IOC; ",
  "excludes arsenic and nitrate, which have their own rule codes). ",
  "ratio = concentration/MCL; near_mcl = reading at 50-100\\% of MCL.",
  ars_clause, " SEs clustered at the CWS (PWSID) level."
)
main_models  <- if (have_ars) list(ars, nit, pool)   else list(nit, pool)
main_headers <- if (have_ars) c("Arsenic", "Nitrate", "Pooled inorganic") else c("Nitrate", "Pooled inorganic")
do.call(etable, c(main_models,
       list(title     = "MR Violations and Prior-Month Contaminant Concentration (CWS-Month Panel)",
            label     = "tab:mr_concentration_lag",
            headers   = main_headers,
            notes     = note_main,
            fitstat   = ~r2 + n,
            style.tex = style.tex("aer", adjustbox = TRUE),
            postprocess.tex = move_notes_below_adjustbox,
            file      = out_tex,
            replace   = TRUE)))
cat(sprintf("\nTable saved to: %s\n", out_tex))

out_tex_placebo <- file.path(ROOT, "output/reg/mr_concentration_lag_placebo.tex")
ars_clause_p <- if (have_ars_placebo) {
  ""
} else {
  " Arsenic lead-placebo omitted: dependent variable is constant (no arsenic MR violations in months with a lead reading)."
}
note_placebo <- paste0(
  "Lead placebo: independent variables are the 1-month LEAD of ratio and near_mcl ",
  "(i.e., next month's reading). If the causal direction runs from high concentration ",
  "to subsequent avoidance, future readings should not predict current MR violations. ",
  "Same outcome, sample, and fixed effects as the main table.",
  ars_clause_p, " SEs clustered at the CWS (PWSID) level."
)
placebo_models   <- if (have_ars_placebo) list(ars_p, nit_p, pool_p) else list(nit_p, pool_p)
placebo_headers  <- if (have_ars_placebo) c("Arsenic", "Nitrate", "Pooled inorganic") else c("Nitrate", "Pooled inorganic")
do.call(etable, c(placebo_models,
       list(title     = "Placebo: MR Violations and Next-Month Contaminant Concentration (Lead Test)",
            label     = "tab:mr_concentration_lag_placebo",
            headers   = placebo_headers,
            notes     = note_placebo,
            fitstat   = ~r2 + n,
            style.tex = style.tex("aer", adjustbox = TRUE),
            postprocess.tex = move_notes_below_adjustbox,
            file      = out_tex_placebo,
            replace   = TRUE)))
cat(sprintf("Placebo table saved to: %s\n", out_tex_placebo))

for (p in c(out_tex, out_tex_placebo)) {
  if (file.exists(p) && file.info(p)$size > 0) {
    cat(sprintf("Output verified: %s exists and is non-zero.\n", p))
  } else {
    cat(sprintf("[ERROR] %s missing or empty.\n", p))
  }
}
