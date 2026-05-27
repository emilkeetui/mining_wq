# ============================================================
# Script: cws_sulfur_year_iv_investigation.r
# Purpose: Investigate sulfur_i x year_t as alternative instrument.
#
# Key questions:
#   1. Is sulfur_i x year_t absorbed by PWSID + year FEs? No.
#      After PWSID demeaning: sulfur_i x (d_t - 1/T), non-zero.
#      After year demeaning: (sulfur_i - mean_i) x (d_t - 1/T).
#   2. Is it estimable with fixest i(year, sulfur)? Yes.
#   3. How do results compare to post95 x sulfur?
#   4. Does it restore identification in 1998-2005 (where post95
#      x sulfur collapses to a PWSID constant, absorbed by PWSID FE)?
#
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review.parquet
# Outputs: console
# Author: EK  Date: 2026-05-26
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)

PROJECT_ROOT <- "Z:/ek559/mining_wq"
PANEL_PATH   <- file.path(PROJECT_ROOT, "clean_data", "cws_data", "prod_vio_sulfur.parquet")
SIX_YR_PATH  <- file.path(PROJECT_ROOT, "clean_data", "cws_6year_review.parquet")

COALVAR  <- "num_coal_mines_upstream_sum"
CONTROLS <- "num_facilities"
FE_STR   <- "PWSID + year"

# ---------------------------------------------------------------------------
# Load full 1985-2005 downstream panel
# ---------------------------------------------------------------------------
cat("=== Loading data ===\n")
panel <- read_parquet(PANEL_PATH)
panel <- panel[panel$year >= 1985 & panel$year <= 2005, ]
panel <- panel[panel$PWSID != "WV3303401", ]
panel_dwnstrm <- panel[panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0, ]
panel_dwnstrm$year_fac <- factor(panel_dwnstrm$year)
cat("Full downstream panel: n =", nrow(panel_dwnstrm), "\n\n")

# ---------------------------------------------------------------------------
# SECTION 1: First-stage comparison (1985-2005)
# ---------------------------------------------------------------------------
cat("=== SECTION 1: First-stage comparison (1985-2005 downstream) ===\n\n")

f_fs_orig <- as.formula(paste0(
  COALVAR, " ~ post95:sulfur_unified_sum + ", CONTROLS, " | ", FE_STR
))
fs_orig <- fixest::feols(f_fs_orig, data = panel_dwnstrm, cluster = ~PWSID)
t_orig  <- coef(fs_orig)["post95:sulfur_unified_sum"] / se(fs_orig)["post95:sulfur_unified_sum"]
f_orig  <- round(t_orig^2, 2)
cat("Original instrument (post95 x sulfur):\n")
print(summary(fs_orig))
cat("Clustered F-stat:", f_orig, "\n\n")

f_fs_new <- as.formula(paste0(
  COALVAR, " ~ i(year_fac, sulfur_unified_sum, ref='1985') + ",
  CONTROLS, " | ", FE_STR
))
fs_new <- fixest::feols(f_fs_new, data = panel_dwnstrm, cluster = ~PWSID)
cat("New instrument (sulfur x year dummies, ref=1984):\n")
print(summary(fs_new))

sulfur_year_coefs <- grep("sulfur_unified_sum", names(coef(fs_new)), value = TRUE)
cat("\nYear-specific sulfur x coal coefficients:\n")
print(round(coef(fs_new)[sulfur_year_coefs], 4))

wald_new <- tryCatch(
  fixest::wald(fs_new, keep = "sulfur_unified_sum"),
  error = function(e) { cat("wald() error:", conditionMessage(e), "\n"); NULL }
)
if (!is.null(wald_new)) {
  cat("\nJoint Wald test (all sulfur x year instruments):\n")
  print(wald_new)
}

# ---------------------------------------------------------------------------
# SECTION 2: 2SLS comparison on original violation data (1985-2005)
# ---------------------------------------------------------------------------
cat("\n\n=== SECTION 2: 2SLS results on nitrates_share_days (1985-2005) ===\n\n")

OUT_VIOL <- "nitrates_share_days"
dset_v   <- panel_dwnstrm[!is.na(panel_dwnstrm[[OUT_VIOL]]), ]
dset_v$year_fac <- factor(dset_v$year)
cat("n =", nrow(dset_v), "\n\n")

f_iv_orig <- as.formula(paste0(
  OUT_VIOL, " ~ ", CONTROLS, " | ", FE_STR,
  " | ", COALVAR, " ~ post95:sulfur_unified_sum"
))
iv_orig <- tryCatch(
  fixest::feols(f_iv_orig, data = dset_v, cluster = ~PWSID),
  error = function(e) { cat("IV orig error:", conditionMessage(e), "\n"); NULL }
)
if (!is.null(iv_orig)) {
  cat("2SLS (post95 x sulfur):\n")
  print(summary(iv_orig))
}

f_iv_new <- as.formula(paste0(
  OUT_VIOL, " ~ ", CONTROLS, " | ", FE_STR,
  " | ", COALVAR, " ~ i(year_fac, sulfur_unified_sum, ref='1985')"
))
iv_new <- tryCatch(
  fixest::feols(f_iv_new, data = dset_v, cluster = ~PWSID),
  error = function(e) { cat("IV new error:", conditionMessage(e), "\n"); NULL }
)
if (!is.null(iv_new)) {
  cat("\n2SLS (sulfur x year dummies):\n")
  print(summary(iv_new))
}

cat("\n--- Coefficient comparison: effect of coal mines on nitrates ---\n")
cat(sprintf("%-35s %10s %10s %10s\n", "Estimator", "Coef", "SE", "F-stat"))
cat(strrep("-", 67), "\n")
if (!is.null(iv_orig)) {
  b <- coef(iv_orig)[COALVAR]; s <- se(iv_orig)[COALVAR]
  cat(sprintf("%-35s %10.4f %10.4f %10.2f\n", "2SLS (post95 x sulfur)", b, s, f_orig))
}
if (!is.null(iv_new)) {
  b <- coef(iv_new)[COALVAR]; s <- se(iv_new)[COALVAR]
  f_joint <- if (!is.null(wald_new)) round(wald_new$stat, 2) else NA
  cat(sprintf("%-35s %10.4f %10.4f %10s\n", "2SLS (sulfur x year)", b, s,
              paste0(f_joint, " (joint)")))
}

# ---------------------------------------------------------------------------
# SECTION 3: sulfur x year on 6-Year Review data (1998-2005)
# ---------------------------------------------------------------------------
cat("\n\n=== SECTION 3: sulfur x year on 6-Year Review (1998-2005) ===\n")
cat("post95=1 always in 1998-2005 => post95 x sulfur collapses to\n")
cat("a PWSID-level constant absorbed by PWSID FE. sulfur x year_t\n")
cat("varies year-to-year within 1998-2005 and is NOT absorbed.\n\n")

df6 <- read_parquet(SIX_YR_PATH)
df6 <- df6[df6$year >= 1985 & df6$year <= 2005, ]
df6 <- df6[df6$PWSID != "WV3303401", ]
df6_dwnstrm <- df6[df6$minehuc_downstream_of_mine == 1 & df6$minehuc_mine == 0, ]
df6_dwnstrm$year_fac <- factor(df6_dwnstrm$year)

for (chem in c("arsenic", "nitrate")) {
  cat("\n--- Chemical:", chem, "---\n")
  chem_data <- df6_dwnstrm[df6_dwnstrm$CHEMID_name == chem & !is.na(df6_dwnstrm$VALUE), ]
  cat("n (non-missing VALUE):", nrow(chem_data), "\n")
  if (nrow(chem_data) < 30) { cat("Too few obs — skipping.\n"); next }

  chem_data$year_fac <- factor(chem_data$year)

  f_fs6 <- as.formula(paste0(
    COALVAR, " ~ i(year_fac, sulfur_unified_sum, ref='1998') + ",
    CONTROLS, " | ", FE_STR
  ))
  fs6 <- tryCatch(
    fixest::feols(f_fs6, data = chem_data, cluster = ~PWSID),
    error = function(e) { cat("FS error:", conditionMessage(e), "\n"); NULL }
  )
  if (!is.null(fs6)) {
    s_coefs <- grep("sulfur_unified_sum", names(coef(fs6)), value = TRUE)
    cat("First-stage sulfur x year coefs:\n")
    print(round(coef(fs6)[s_coefs], 4))
    w6 <- tryCatch(fixest::wald(fs6, keep = "sulfur_unified_sum"), error = function(e) NULL)
    if (!is.null(w6)) cat("Joint F-stat (sulfur x year):", round(w6$stat, 2), "\n")
  }

  f_iv6 <- as.formula(paste0(
    "VALUE ~ ", CONTROLS, " | ", FE_STR,
    " | ", COALVAR, " ~ i(year_fac, sulfur_unified_sum, ref='1998')"
  ))
  iv6 <- tryCatch(
    fixest::feols(f_iv6, data = chem_data, cluster = ~PWSID),
    error = function(e) { cat("2SLS error:", conditionMessage(e), "\n"); NULL }
  )
  if (!is.null(iv6)) {
    b <- coef(iv6)[COALVAR]; s <- se(iv6)[COALVAR]
    cat(sprintf("2SLS (sulfur x year): coef = %.4f, se = %.4f, t = %.2f\n", b, s, b/s))
  }

  f_ols6 <- as.formula(paste0("VALUE ~ ", COALVAR, " + ", CONTROLS, " | ", FE_STR))
  ols6 <- tryCatch(
    fixest::feols(f_ols6, data = chem_data, cluster = ~PWSID),
    error = function(e) { cat("OLS error:", conditionMessage(e), "\n"); NULL }
  )
  if (!is.null(ols6)) {
    b <- coef(ols6)[COALVAR]; s <- se(ols6)[COALVAR]
    cat(sprintf("OLS:                  coef = %.4f, se = %.4f, t = %.2f\n", b, s, b/s))
  }
}

cat("\nDone.\n")
