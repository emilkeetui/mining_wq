# ============================================================
# Script: ks_static_feasibility.r
# Purpose: Three feasibility checks for the K&S static structural
#          model (§9 of 2026-05-22-kang-silveira-static-structural-proposal.md)
#            1. Poisson/NB dispersion of K_it (MR violation-days)
#            2. Meaningful k-variation in enforcement schedule (Eq. 2a)
#            3. LPV monotonicity of G(a|x) across IV-bins
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: console report
#          output/fig/ks_feasibility_lpv_monotonicity.png
# Author: EK  Date: 2026-05-22
# ============================================================

suppressPackageStartupMessages({
  library(arrow)
  library(fixest)
  library(dplyr)
  library(data.table)
  library(ggplot2)
})

# ---- Sample: downstream CWSs, 1985-2005 (matches proposal §4.1) ----
df <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
df <- df[df$PWSID != "WV3303401", ]

panel <- df |>
  filter(
    minehuc_downstream_of_mine == 1,
    minehuc_mine == 0,
    year >= 1985, year <= 2005,
    !is.na(sulfur_unified_mean),
    !is.na(post95),
    !is.na(num_coal_mines_upstream_mean),
    !is.na(num_facilities)
  )
panel$state <- panel$STATE_CODE
# Alias to keep proposal-notation consistent
panel$sulfur_unified         <- panel$sulfur_unified_mean
panel$num_coal_mines_upstream <- panel$num_coal_mines_upstream_mean

mining_outcomes <- c("nitrates", "arsenic", "inorganic_chemicals", "radionuclides")
mr_vars <- paste0(mining_outcomes, "_MR_share_days")

# Build K_it: pooled MR violation-days across mining-related contaminants.
# *_MR_share_days is fraction of year; multiply by 365 to get days.
for (v in mr_vars) {
  panel[[paste0(v, "_count")]] <- round(pmax(0, panel[[v]]) * 365)
}
count_vars <- paste0(mr_vars, "_count")
panel$K <- rowSums(panel[, count_vars], na.rm = TRUE)
panel$K <- pmin(panel$K, 365)  # cap at 365

pwsids <- unique(panel$PWSID)

cat("==========================================================\n")
cat("K&S STATIC STRUCTURAL — FEASIBILITY CHECKS (§9)\n")
cat("Sample: downstream CWSs, 1985-2005\n")
cat("==========================================================\n")
cat(sprintf("N obs (PWSID x year):  %d\n", nrow(panel)))
cat(sprintf("N unique PWSIDs:       %d\n\n", length(pwsids)))


# ==========================================================
# CHECK 1: Poisson / NB dispersion of K_it
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 1: Is K_it Poisson-like? (Lemma 1 prerequisite)\n")
cat("----------------------------------------------------------\n")

K <- panel$K
n_zero <- sum(K == 0)
n_one  <- sum(K == 1)
n_pos  <- sum(K > 0)
mu     <- mean(K)
v      <- var(K)
disp   <- v / mu

cat(sprintf("K_it (pooled MR days, mining outcomes):\n"))
cat(sprintf("  mean         : %.3f\n", mu))
cat(sprintf("  variance     : %.3f\n", v))
cat(sprintf("  var / mean   : %.2f   (Poisson => 1; finite NB if moderate)\n", disp))
cat(sprintf("  share zero   : %.1f%%\n", 100 * n_zero / length(K)))
cat(sprintf("  share K=1    : %.2f%%\n", 100 * n_one  / length(K)))
cat(sprintf("  share K > 0  : %.2f%%\n", 100 * n_pos  / length(K)))
cat(sprintf("  max K        : %d\n", max(K)))

cat("\nDistribution of nonzero K_it (deciles):\n")
print(round(quantile(K[K > 0], probs = seq(0.1, 1, 0.1)), 1))

# Fit a negative binomial and report dispersion (theta)
cat("\nNegative-binomial fit (intercept only):\n")
nb_fit <- tryCatch(
  MASS::glm.nb(K ~ 1, data = panel),
  error = function(e) NULL
)
if (!is.null(nb_fit)) {
  cat(sprintf("  NB theta (size)     : %.3f   (large => Poisson; small => overdispersed)\n",
              nb_fit$theta))
  cat(sprintf("  NB theta SE         : %.3f\n", nb_fit$SE.theta))
}

# Verdict
cat("\nVerdict:\n")
if (n_pos / length(K) < 0.02) {
  cat("  K is overwhelmingly 0/1 (too binary). Poisson mixture identification\n")
  cat("  in K&S Lemma 1 will degenerate. Recommend reframing on Bernoulli choice.\n")
} else if (disp > 50) {
  cat("  Severe overdispersion. Poisson misfit; NB may be unstable.\n")
} else if (disp > 5) {
  cat("  Heavy overdispersion (var/mean = %.1f). NB feasible but check tail fit.\n")
} else {
  cat("  K has usable count variation. Poisson-Gamma (NB) mixture should hold.\n")
}
cat("\n")


# ==========================================================
# CHECK 2: Enforcement schedule has meaningful k-variation
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 2: Does Pr(E=1) respond to K?  (Eq. 2a phi_1 != 0)\n")
cat("----------------------------------------------------------\n")

enf_path <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv"
enf_raw <- fread(enf_path, select = c(
  "PWSID", "COMPL_PER_BEGIN_DATE", "ENF_ACTION_CATEGORY",
  "ENFORCEMENT_ACTION_TYPE_CODE", "VIOLATION_CATEGORY_CODE"
), colClasses = "character")
enf_raw[, year := as.integer(substr(COMPL_PER_BEGIN_DATE, 7, 10))]

enf <- enf_raw[PWSID %in% pwsids & year >= 1985 & year <= 2005]

# Indicator: any formal/informal enforcement action for the CWS-year
enf_action <- enf[ENF_ACTION_CATEGORY %in% c("Formal", "Informal", "Resolving"),
                  .(any_enf = 1L), by = .(PWSID, year)]

panel <- merge(panel, enf_action, by = c("PWSID", "year"), all.x = TRUE)
panel$any_enforcement <- ifelse(is.na(panel$any_enf), 0L, 1L)
panel$any_enf <- NULL

# Subsample of PWSIDs that ever appear in enforcement file (the 268)
enf_pwsids <- unique(enf$PWSID)
enf_panel  <- panel[panel$PWSID %in% enf_pwsids, ]
cat(sprintf("PWSIDs with any enforcement record: %d / %d\n",
            length(enf_pwsids), length(pwsids)))
cat(sprintf("Enforcement subsample obs:          %d\n", nrow(enf_panel)))
cat(sprintf("Share of CWS-years with any_enforcement=1: %.2f%%\n",
            100 * mean(enf_panel$any_enforcement)))
cat(sprintf("Mean K_it in this subsample: %.2f\n\n", mean(enf_panel$K)))

# Eq. 2a: probit Pr(E=1) ~ K + K^2 + x
fit_2a <- glm(
  any_enforcement ~ K + I(K^2) +
    num_facilities + POPULATION_SERVED_COUNT +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE),
  family = binomial(link = "probit"),
  data   = enf_panel
)

cat("Probit fit (Eq. 2a): Pr(any_enforcement=1) ~ K + K^2 + x\n")
s <- summary(fit_2a)$coefficients
keep <- intersect(c("K", "I(K^2)"), rownames(s))
print(round(s[keep, , drop = FALSE], 5))

phi1 <- if ("K"      %in% keep) s["K",      "Estimate"]   else NA_real_
se1  <- if ("K"      %in% keep) s["K",      "Std. Error"] else NA_real_
phi2 <- if ("I(K^2)" %in% keep) s["I(K^2)", "Estimate"]   else NA_real_
se2  <- if ("I(K^2)" %in% keep) s["I(K^2)", "Std. Error"] else NA_real_

cat(sprintf("\n  phi_1 (linear)    : %s   (t = %s)\n",
            formatC(phi1, digits = 5, format = "f"),
            ifelse(is.na(phi1), "NA", formatC(phi1 / se1, digits = 2, format = "f"))))
cat(sprintf("  phi_2 (quadratic) : %s   (t = %s)\n",
            formatC(phi2, digits = 5, format = "f"),
            ifelse(is.na(phi2), "NA", formatC(phi2 / se2, digits = 2, format = "f"))))

# Marginal effects at K = 0, mean(K), and 90th percentile
k_grid <- c(0, mean(enf_panel$K), quantile(enf_panel$K, 0.9))
nd <- data.frame(
  K = k_grid, num_facilities = median(enf_panel$num_facilities),
  POPULATION_SERVED_COUNT = median(enf_panel$POPULATION_SERVED_COUNT, na.rm = TRUE),
  OWNER_TYPE_CODE = names(sort(table(enf_panel$OWNER_TYPE_CODE), decreasing = TRUE))[1],
  PRIMARY_SOURCE_CODE = names(sort(table(enf_panel$PRIMARY_SOURCE_CODE), decreasing = TRUE))[1]
)
nd$pr_e <- predict(fit_2a, newdata = nd, type = "response")
cat("\nPredicted Pr(E=1) on the K-grid:\n")
print(data.frame(K = round(k_grid, 1), pr_E = round(nd$pr_e, 4)))

# Verdict: |t| on K + K^2 > 2 (joint Wald)
wald <- tryCatch({
  if (length(keep) == 0) {
    NA_real_
  } else {
    Vb <- vcov(fit_2a)[keep, keep, drop = FALSE]
    bb <- coef(fit_2a)[keep]
    as.numeric(t(bb) %*% solve(Vb) %*% bb)
  }
}, error = function(e) NA_real_)

cat(sprintf("\nWald chi-sq (K and K^2 joint = 0):  %.2f   (chi2_2 95%% crit = 5.99)\n", wald))
cat("\nVerdict:\n")
if (is.na(wald)) {
  cat("  Could not invert covariance; inspect fit_2a manually.\n")
} else if (wald < 5.99) {
  cat("  Pr(E=1) is FLAT in K. e'(a) ~ 0 and firm FOC is uninformative.\n")
  cat("  Structural penalty-design analysis is NOT supported by this enforcement data.\n")
} else if (abs(phi1 / se1) < 2 && abs(phi2 / se2) < 2) {
  cat("  Joint nonzero but each piece weak; consider polynomial reparametrization.\n")
} else {
  cat("  Pr(E=1) responds to K.  Penalty schedule has usable curvature.\n")
}
cat("\n")


# ==========================================================
# CHECK 3: LPV monotonicity across IV-bins
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 3: Is G(a|x) stochastically ordered in the IV?  (LPV)\n")
cat("----------------------------------------------------------\n")

# IV value: post95 * sulfur_unified (continuous shifter)
panel$z <- panel$post95 * panel$sulfur_unified

# Restrict to post-1995 obs where the instrument has bite.
# Within post95==1, z = sulfur_unified, which is time-invariant per PWSID,
# so a first-stage residual collapses against PWSID FE.  Bin directly on
# the IV value — LPV monotonicity is a statement about G(a|x), and x is
# what the IV exogenously shifts.
post <- panel[panel$post95 == 1, ]
cat(sprintf("Post-95 obs (where z varies): %d\n", nrow(post)))

brks <- unique(quantile(post$z[post$z > 0], probs = c(0, 0.25, 0.5, 0.75, 1),
                        na.rm = TRUE))
post$z_bin <- cut(post$z, breaks = c(-Inf, brks[-1]),
                  labels = paste0("Q", seq_len(length(brks) - 1)),
                  include.lowest = TRUE)
post$z_bin <- droplevels(post$z_bin)

cat("\nMean K_it by IV quartile (post-1995):\n")
mean_by_bin <- aggregate(K ~ z_bin, data = post, FUN = mean)
print(mean_by_bin)

# Empirical CDF of K_it within each bin on a common grid; check FOSD pairwise
grid <- sort(unique(c(0, 1, 2, 5, 10, 20, 30, 60, 90, 180, 365)))
ecdfs <- lapply(levels(post$z_bin), function(b) {
  x <- post$K[post$z_bin == b]
  data.frame(z_bin = b, K = grid, F_K = ecdf(x)(grid))
})
ecdf_df <- do.call(rbind, ecdfs)

cat("\nEmpirical Pr(K <= k) by IV quartile:\n")
ecdf_wide <- reshape(ecdf_df, idvar = "K", timevar = "z_bin", direction = "wide")
print(round(ecdf_wide, 3))

# Stochastic-ordering check: for each pair (q_low, q_high), count grid points
# where F_high(k) <= F_low(k) (i.e., high-IV bin FOSD-dominates low-IV bin).
bins <- levels(post$z_bin)
cat("\nFOSD check: share of grid points where F_high(k) <= F_low(k)\n")
cat("(should be ~1.0 if high-z bin stochastically dominates low-z bin)\n\n")

for (i in seq_along(bins)) {
  for (j in seq_along(bins)) {
    if (j <= i) next
    Fi <- ecdf_df$F_K[ecdf_df$z_bin == bins[i]]
    Fj <- ecdf_df$F_K[ecdf_df$z_bin == bins[j]]
    pct <- mean(Fj <= Fi + 1e-8)
    cat(sprintf("  %s vs %s: %.0f%%\n", bins[j], bins[i], 100 * pct))
  }
}

# Pairwise Kolmogorov-Smirnov for the top vs bottom IV bin
ks <- tryCatch(
  ks.test(post$K[post$z_bin == "Q4"], post$K[post$z_bin == "Q1"]),
  error = function(e) NULL, warning = function(w) NULL
)
if (!is.null(ks)) {
  cat(sprintf("\nKS test Q4 vs Q1: D = %.3f, p = %.4f\n", ks$statistic, ks$p.value))
}

# Save eCDF plot to output/fig/
dir.create("output/fig", showWarnings = FALSE, recursive = TRUE)
p <- ggplot(ecdf_df, aes(x = K, y = F_K, colour = z_bin)) +
  geom_step(linewidth = 0.9) +
  labs(x = "K  (MR violation-days)",
       y = expression(hat(G)(K * "|" * x)),
       colour = "IV quartile",
       title = NULL) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())
ggsave("output/fig/ks_feasibility_lpv_monotonicity.png",
       plot = p, width = 6, height = 4, dpi = 200)
cat("\nWrote: output/fig/ks_feasibility_lpv_monotonicity.png\n")

cat("\nVerdict:\n")
cat("  If F_high(k) <= F_low(k) holds across most of the grid (>= 80%),\n")
cat("  G(a|x) is stochastically ordered in x and LPV identification is supported.\n")
cat("  If the ordering is violated or the curves cross, the one-regime LPV walk\n")
cat("  is not credible and the IV-adapted identification fails.\n")

cat("\n==========================================================\n")
cat("SUMMARY\n")
cat("==========================================================\n")
cat("Check 1 (Poisson dispersion of K) : see var/mean and NB theta above\n")
cat("Check 2 (Enforcement responds to K): see Wald chi-sq above\n")
cat("Check 3 (LPV monotonicity)        : see FOSD share + KS test above\n")
cat("==========================================================\n")
