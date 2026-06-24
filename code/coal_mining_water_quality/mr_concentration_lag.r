# ============================================================
# Script: mr_concentration_lag.r
# Purpose: Test whether MR (monitoring/reporting) violations rise
#          after a CWS observes a high contaminant concentration
#          (regulator-pivot / strategic avoidance mechanism), using
#          the measurement-level downstream-only SYR2 sample built
#          by build_mr_concentration_lag.py.
#          Specs: (A) arsenic, (B) nitrate -- same-contaminant MR
#          violation 1-365 days after the sample; (C) pooled -- MR
#          violation under RULE_CODE==333.0 (Inorganic Chemicals /
#          Other IOC, same definition as `inorganic_chemicals` in
#          2sls_dwnstrm_minevio_allcat_ivsum.tex) 1-365 days after.
#          Forward-window table + past-window placebo table (placebo
#          windows mirror the forward windows: 1-365 days before).
# Inputs:  clean_data/mr_concentration_lag_measurement.parquet
# Outputs: output/reg/mr_concentration_lag.tex
#          output/reg/mr_concentration_lag_placebo.tex
# Author: EK  Date: 2026-06-23
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(fixest)

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

# ── Step 1: Load + schema check ───────────────────────────────────────────────
cat("Loading measurement-level analysis dataset...\n")
df <- read_parquet("clean_data/mr_concentration_lag_measurement.parquet")
str(df)   # PWSID must be <chr>, YEAR must be <int>

cat(sprintf("\nRows: %d | unique PWSID: %d | years %d-%d\n",
            nrow(df), length(unique(df$PWSID)), min(df$YEAR), max(df$YEAR)))
cat("Chemicals present:\n")
print(table(df$CHEMID_name))

ars_df  <- df[df$contaminant_code == "1005", ]
nit_df  <- df[df$contaminant_code == "1040", ]
pool_df <- df

cat(sprintf("\nArsenic (1005) subset N = %d\n", nrow(ars_df)))
cat(sprintf("Nitrate (1040) subset N = %d\n", nrow(nit_df)))
cat(sprintf("Pooled subset N = %d\n", nrow(pool_df)))

# ── Step 2: Named formulas ────────────────────────────────────────────────────
fml_ars  <- mr_same_fwd   ~ ratio + near_mcl | PWSID + YEAR
fml_nit  <- mr_same_fwd   ~ ratio + near_mcl | PWSID + YEAR
fml_pool <- mr_anyioc_fwd ~ ratio + near_mcl | PWSID + YEAR + contaminant_code

fml_ars_placebo  <- mr_same_past   ~ ratio + near_mcl | PWSID + YEAR
fml_nit_placebo  <- mr_same_past   ~ ratio + near_mcl | PWSID + YEAR
fml_pool_placebo <- mr_anyioc_past ~ ratio + near_mcl | PWSID + YEAR + contaminant_code

# Arsenic subset may be empty if too few measurements survive the >10% detection-rate
# filter upstream; feols cannot fit on zero rows, so the Arsenic column is included
# only when nrow(ars_df) > 0.
have_ars <- nrow(ars_df) > 0
if (!have_ars) {
  cat("\n[NOTE] Arsenic subset is empty (N=0) -- arsenic column omitted from both tables.\n")
}

# ── Step 3: Forward-window regressions ────────────────────────────────────────
nit  <- feols(fml_nit,  data = nit_df,  cluster = ~PWSID)
pool <- feols(fml_pool, data = pool_df, cluster = ~PWSID)

cat("\n--- (B) Nitrate, forward window ---\n");  print(summary(nit))
cat("\n--- (C) Pooled any-IOC, forward window ---\n"); print(summary(pool))

if (have_ars) {
  ars <- feols(fml_ars, data = ars_df, cluster = ~PWSID)
  cat("\n--- (A) Arsenic, forward window ---\n"); print(summary(ars))
}

# ── Step 4: Past-window placebo regressions ───────────────────────────────────
nit_p  <- feols(fml_nit_placebo,  data = nit_df,  cluster = ~PWSID)
pool_p <- feols(fml_pool_placebo, data = pool_df, cluster = ~PWSID)

cat("\n--- (B) Nitrate, past-window placebo ---\n");  print(summary(nit_p))
cat("\n--- (C) Pooled any-IOC, past-window placebo ---\n"); print(summary(pool_p))

if (have_ars) {
  ars_p <- feols(fml_ars_placebo, data = ars_df, cluster = ~PWSID)
  cat("\n--- (A) Arsenic, past-window placebo ---\n"); print(summary(ars_p))
}

# ── Step 5: wrap_for_beamer (copied from enforcement_chain_d12.r) ────────────
wrap_for_beamer <- function(path, beamer_height = "0.78\\textheight") {
  header <- c(
    "\\makeatletter",
    paste0("\\@ifclassloaded{beamer}{%\n",
           "  \\begin{adjustbox}{max width=\\linewidth,",
           " max totalheight=", beamer_height, ", center}%\n",
           "}{%\n",
           "  \\begin{adjustbox}{max width=\\linewidth, center}%\n",
           "}%"),
    "\\makeatother"
  )
  lines <- readLines(path)
  note_start  <- grep("^\\\\par \\\\raggedright\\s*$", lines)
  endgroup_ln <- grep("^\\\\par\\\\endgroup\\s*$",     lines)
  if (length(note_start) == 1 && length(endgroup_ln) == 1 && note_start < endgroup_ln) {
    note_text <- lines[(note_start + 1):(endgroup_ln - 1)]
    body      <- c(lines[seq_len(note_start - 1)], "\\par\\endgroup")
    writeLines(c(header, body, "\\end{adjustbox}", "",
                 "\\par \\raggedright", note_text, "\\par"), path)
  } else {
    writeLines(c(header, lines, "\\end{adjustbox}"), path)
  }
}

# ── Step 6: LaTeX tables ──────────────────────────────────────────────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

out_tex <- file.path(ROOT, "output/reg/mr_concentration_lag.tex")
ars_clause <- if (have_ars) {
  ""
} else {
  paste0(
    " Arsenic column omitted: arsenic measurements fail the >10% detection-rate filter ",
    "in this restricted sample and zero arsenic rows survive."
  )
}
note_main <- paste0(
  "Downstream-only mining sample (minehuc_downstream_of_mine==1 & minehuc_mine==0), ",
  "SYR2 only (1998-2005). Forward window: outcome is an MR violation occurring 1-365 ",
  "days after the sample date (same-contaminant MR violation for Arsenic/Nitrate; ",
  "RULE_CODE==333.0 MR violation for Pooled). Pooled any-IOC: MR violation under ",
  "RULE_CODE==333.0 (Inorganic Chemicals / Other IOC -- the same rule code used to build ",
  "`inorganic_chemicals` in 2sls_dwnstrm_minevio_allcat_ivsum.tex; excludes arsenic and ",
  "nitrate, which have their own rule codes). ",
  "ratio = concentration/MCL; near_mcl = reading at 50-100% of MCL.", ars_clause, " SEs ",
  "clustered at the CWS (PWSID) level."
)
main_models  <- if (have_ars) list(ars, nit, pool)   else list(nit, pool)
main_headers <- if (have_ars) c("Arsenic", "Nitrate", "Pooled inorganic") else c("Nitrate", "Pooled inorganic")
do.call(etable, c(main_models,
       list(title   = "MR Violations Following High Contaminant Concentration (Forward Window)",
            headers = main_headers,
            notes   = note_main,
            fitstat = ~r2 + n,
            file    = out_tex,
            replace = TRUE)))
wrap_for_beamer(out_tex)
cat(sprintf("\nTable saved to: %s\n", out_tex))

out_tex_placebo <- file.path(ROOT, "output/reg/mr_concentration_lag_placebo.tex")
ars_clause_p <- if (have_ars) "" else " Arsenic omitted (N=0)."
note_placebo <- paste0(
  "Past-window placebo: outcome is an MR violation occurring 1-365 days BEFORE the ",
  "sample date (same-contaminant MR violation for Arsenic/Nitrate; RULE_CODE==333.0 MR ",
  "violation for Pooled). Pooled any-IOC: MR violation under RULE_CODE==333.0 ",
  "(Inorganic Chemicals / Other IOC -- the same rule code used to build ",
  "`inorganic_chemicals` in 2sls_dwnstrm_minevio_allcat_ivsum.tex; excludes arsenic and ",
  "nitrate, which have their own rule codes). ratio = concentration/MCL; near_mcl = ",
  "reading at 50-100% of MCL. Same sample and FE as the forward-window table.",
  ars_clause_p, " SEs clustered at the CWS (PWSID) level."
)
placebo_models <- if (have_ars) list(ars_p, nit_p, pool_p) else list(nit_p, pool_p)
do.call(etable, c(placebo_models,
       list(title   = "Placebo: MR Violations Preceding High Contaminant Concentration (Past Window)",
            headers = main_headers,
            notes   = note_placebo,
            fitstat = ~r2 + n,
            file    = out_tex_placebo,
            replace = TRUE)))
wrap_for_beamer(out_tex_placebo)
cat(sprintf("Placebo table saved to: %s\n", out_tex_placebo))

for (p in c(out_tex, out_tex_placebo)) {
  if (file.exists(p) && file.info(p)$size > 0) {
    cat(sprintf("Output verified: %s exists and is non-zero.\n", p))
  } else {
    cat(sprintf("[ERROR] %s missing or empty.\n", p))
  }
}
