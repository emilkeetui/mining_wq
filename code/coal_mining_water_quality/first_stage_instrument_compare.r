# ============================================================
# Script: first_stage_instrument_compare.r
# Purpose: Compare first-stage strength of candidate sulfur instruments
#          for the downstream inorganic-MR 2SLS, with and without PA.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet       (sum / mean variants)
#          clean_data/cws_data/prod_vio_sulfur_4step.parquet (upstream variant)
# Outputs: console only (diagnostic)
# Author: EK  Date: 2026-06-06
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(fixest)

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

# Helper: run the MR 2SLS and pull the first-stage F (default + clustered t^2)
fs_report <- function(data, treat, instr, fe, label) {
  fml <- as.formula(sprintf(
    "inorganic_chemicals_MR_share_days ~ num_facilities | %s | %s ~ %s",
    fe, treat, instr))
  fit <- feols(fml, data = data, cluster = ~ PWSID)
  ivf <- fitstat(fit, "ivf")[[1]]$stat          # standard (non-clustered) 1st-stage F
  # clustered first-stage F = (clustered t on the instrument)^2 from the 1st-stage reg
  fs_fml <- as.formula(sprintf("%s ~ %s + num_facilities | %s", treat, instr, fe))
  fs <- feols(fs_fml, data = data, cluster = ~ PWSID)
  tval <- coef(fs)[grep(":", names(coef(fs)))[1]] / se(fs)[grep(":", names(se(fs)))[1]]
  cat(sprintf("%-46s  N=%-6d  iv-F=%9.2f  clustered-F=%8.2f  beta_2sls=%8.4f\n",
              label, nobs(fit), ivf, tval^2,
              coef(fit)[grep("num_coal_mines", names(coef(fit)))[1]]))
}

# ---------- sum / mean variants: prod_vio_sulfur.parquet ----------
df <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
df <- df[df$PWSID != "WV3303401", ]
s_main <- df[df$minehuc_downstream_of_mine == 1 & df$minehuc_mine == 0 &
             df$year >= 1985 & df$year <= 2005 &
             !is.na(df$post95), ]
s_main$state <- substr(s_main$PWSID, 1, 2)
s_main_noPA <- s_main[s_main$state != "PA", ]

cat("\n================ DOWNSTREAM INORGANIC-MR FIRST STAGE ================\n")
cat("--- WITH PA (FE: PWSID + year) ---\n")
fs_report(s_main, "num_coal_mines_upstream_sum", "post95:sulfur_unified_sum",  "PWSID + year", "post95 x sulfur_unified_sum")
fs_report(s_main, "num_coal_mines_upstream_sum", "post95:sulfur_unified_mean", "PWSID + year", "post95 x sulfur_unified_mean")

cat("\n--- WITHOUT PA (FE: PWSID + year) ---\n")
fs_report(s_main_noPA, "num_coal_mines_upstream_sum", "post95:sulfur_unified_sum",  "PWSID + year", "post95 x sulfur_unified_sum")
fs_report(s_main_noPA, "num_coal_mines_upstream_sum", "post95:sulfur_unified_mean", "PWSID + year", "post95 x sulfur_unified_mean")

cat("\n--- WITHOUT PA (FE: PWSID + year + STATE_CODE) ---\n")
fs_report(s_main_noPA, "num_coal_mines_upstream_sum", "post95:sulfur_unified_sum",  "PWSID + year + STATE_CODE", "post95 x sulfur_unified_sum")
fs_report(s_main_noPA, "num_coal_mines_upstream_sum", "post95:sulfur_unified_mean", "PWSID + year + STATE_CODE", "post95 x sulfur_unified_mean")

# ---------- upstream variant: prod_vio_sulfur_4step.parquet ----------
cat("\n--- upstream variant (different treatment/sample; FE: PWSID + year) ---\n")
df4 <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur_4step.parquet")
df4 <- df4[df4$PWSID != "WV3303401", ]
has_mr <- "inorganic_chemicals_MR_share_days" %in% names(df4)
cat(sprintf("4step has inorganic_chemicals_MR_share_days: %s\n", has_mr))
if (has_mr) {
  s4 <- df4[df4$minehuc_downstream_of_mine == 1 & df4$minehuc_mine == 0 &
            df4$year >= 1985 & df4$year <= 2005 &
            !is.na(df4$post95) & !is.na(df4$sulfur_upstream), ]
  s4$state <- substr(s4$PWSID, 1, 2)
  s4_noPA <- s4[s4$state != "PA", ]
  fs_report(s4,      "num_coal_mines_upstream", "post95:sulfur_upstream", "PWSID + year", "post95 x sulfur_upstream  [WITH PA]")
  fs_report(s4_noPA, "num_coal_mines_upstream", "post95:sulfur_upstream", "PWSID + year", "post95 x sulfur_upstream  [NO PA]")
}
cat("\nDone.\n")
