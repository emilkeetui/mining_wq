# ============================================================
# Script: binary_feasibility.r
# Purpose: Feasibility checks for the BINARY-CHOICE variant of the
#          K&S static structural model
#          (§9 of 2026-05-22-kang-silveira-static-structural-proposal.md).
#          Three tests:
#            1. Enforcement responds to B (carry-over from Check 2)
#            2. Cross-IV-bin variance of Delta_e_hat(x)
#               -> can F(theta|x) be traced at multiple theta points?
#            3. Monotonicity of p_hat(x) = Pr(B=1|x) in the IV
#               -> binary analogue of LPV stochastic ordering
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: console report
#          output/fig/binary_feasibility_p_hat_by_iv.png
# Author: EK  Date: 2026-05-22
# ============================================================

suppressPackageStartupMessages({
  library(arrow)
  library(fixest)
  library(dplyr)
  library(data.table)
  library(ggplot2)
})

# ---- Sample ----
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
panel$state           <- panel$STATE_CODE
panel$sulfur_unified  <- panel$sulfur_unified_mean
panel$num_coal_mines_upstream <- panel$num_coal_mines_upstream_mean
panel$z               <- panel$post95 * panel$sulfur_unified

# Binary firm action: any MR violation across mining-related contaminants
mining   <- c("nitrates", "arsenic", "inorganic_chemicals", "radionuclides")
mr_vars  <- paste0(mining, "_MR_share_days")
panel$B  <- as.integer(rowSums(panel[, mr_vars], na.rm = TRUE) > 0)

pwsids <- unique(panel$PWSID)

cat("==========================================================\n")
cat("BINARY-CHOICE K&S — FEASIBILITY CHECKS\n")
cat("Sample: downstream CWSs, 1985-2005\n")
cat("==========================================================\n")
cat(sprintf("N obs (PWSID x year):  %d\n", nrow(panel)))
cat(sprintf("N unique PWSIDs:       %d\n", length(pwsids)))
cat(sprintf("Share B=1:             %.2f%%\n\n", 100 * mean(panel$B)))


# ==========================================================
# CHECK 1: Enforcement responds to B
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 1: Pr(E=1) responds to B   (Eq. 2a, phi_B != 0)\n")
cat("----------------------------------------------------------\n")

enf_path <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv"
enf_raw  <- fread(enf_path, select = c(
  "PWSID", "COMPL_PER_BEGIN_DATE", "ENF_ACTION_CATEGORY",
  "ENFORCEMENT_ACTION_TYPE_CODE", "CALCULATED_RTC_DATE"
), colClasses = "character")
enf_raw[, year := as.integer(substr(COMPL_PER_BEGIN_DATE, 7, 10))]
enf <- enf_raw[PWSID %in% pwsids & year >= 1985 & year <= 2005]

# Annual indicator: any formal/informal/resolving enforcement action
enf_action <- enf[ENF_ACTION_CATEGORY %in% c("Formal", "Informal", "Resolving"),
                  .(any_enf = 1L), by = .(PWSID, year)]
panel <- merge(panel, enf_action, by = c("PWSID", "year"), all.x = TRUE)
panel$any_enforcement <- ifelse(is.na(panel$any_enf), 0L, 1L)
panel$any_enf <- NULL

# Annual days_to_RTC for E=1 obs
enf[, viol_date := as.Date(COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
enf[, rtc_date  := as.Date(CALCULATED_RTC_DATE,  format = "%m/%d/%Y")]
enf[, days_to_rtc := as.numeric(rtc_date - viol_date)]
enf_valid <- enf[!is.na(days_to_rtc) & days_to_rtc >= 0 & days_to_rtc <= 3650]
rtc_annual <- enf_valid[, .(days_to_RTC = median(days_to_rtc, na.rm = TRUE)),
                        by = .(PWSID, year)]
panel <- merge(panel, rtc_annual, by = c("PWSID", "year"), all.x = TRUE)

enf_pwsids <- unique(enf$PWSID)
enf_panel  <- panel[panel$PWSID %in% enf_pwsids, ]
cat(sprintf("PWSIDs in enforcement subsample: %d / %d\n",
            length(enf_pwsids), length(pwsids)))
cat(sprintf("Obs in enforcement subsample:    %d\n", nrow(enf_panel)))
cat(sprintf("Mean any_enforcement:            %.3f\n", mean(enf_panel$any_enforcement)))
cat(sprintf("Mean B in this subsample:        %.3f\n\n", mean(enf_panel$B)))

# Eq. 2a: probit Pr(E=1) ~ B + x  (with control function residual v_hat)
fit_1 <- feols(
  num_coal_mines_upstream ~ z + num_facilities |
    PWSID + year + state,
  data = panel, cluster = ~PWSID, fixef.rm = "none"
)
# Some fixest versions still drop singletons; align by index.
r1 <- residuals(fit_1)
panel$v_hat <- NA_real_
if (length(r1) == nrow(panel)) {
  panel$v_hat <- r1
} else {
  keep_idx <- as.integer(rownames(model.matrix(fit_1)))
  if (length(keep_idx) == length(r1)) {
    panel$v_hat[keep_idx] <- r1
  } else {
    # last-resort: compute v_hat from raw fitted predictions
    panel$v_hat <- panel$num_coal_mines_upstream -
                   predict(fit_1, newdata = panel)
  }
}
enf_panel <- merge(enf_panel,
                   panel[, c("PWSID", "year", "v_hat")],
                   by = c("PWSID", "year"), all.x = TRUE)

fit_2a <- glm(
  any_enforcement ~ B + num_facilities + POPULATION_SERVED_COUNT +
                    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + v_hat,
  family = binomial(link = "probit"), data = enf_panel
)
s2a <- summary(fit_2a)$coefficients
cat("Probit (Eq. 2a): Pr(any_enforcement = 1) ~ B + x + v_hat\n")
print(round(s2a[c("(Intercept)", "B"), , drop = FALSE], 5))

phi_B  <- s2a["B", "Estimate"]
seB    <- s2a["B", "Std. Error"]
cat(sprintf("\n  phi_B            : %.5f   (t = %.2f, p = %.4g)\n",
            phi_B, phi_B / seB, s2a["B", "Pr(>|z|)"]))

# Predicted Pr(E=1) at B=0 vs B=1 (other x at their medians)
nd <- data.frame(
  B = c(0, 1),
  num_facilities = median(enf_panel$num_facilities),
  POPULATION_SERVED_COUNT = median(enf_panel$POPULATION_SERVED_COUNT, na.rm = TRUE),
  OWNER_TYPE_CODE     = names(sort(table(enf_panel$OWNER_TYPE_CODE), decreasing = TRUE))[1],
  PRIMARY_SOURCE_CODE = names(sort(table(enf_panel$PRIMARY_SOURCE_CODE), decreasing = TRUE))[1],
  v_hat = 0
)
nd$pr_e <- predict(fit_2a, newdata = nd, type = "response")
cat("\n  Predicted Pr(E=1) at the modal x, v_hat=0:\n")
print(data.frame(B = nd$B, pr_E = round(nd$pr_e, 4)))

cat("\nVerdict:\n")
if (is.na(phi_B) || abs(phi_B / seB) < 2) {
  cat("  Pr(E=1) does NOT respond to B. Enforcement schedule is flat.\n")
  cat("  Firm FOC is uninformative; structural project should be reframed.\n")
} else {
  cat("  Pr(E=1) responds to B. Schedule has deterrence content.\n")
}
cat("\n")


# ==========================================================
# CHECK 2: Cross-IV-bin variance of Delta_e_hat(x)
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 2: Variation in Delta_e_hat(x) across IV-bins\n")
cat("----------------------------------------------------------\n")

# Eq. 2b: log(days_to_RTC + 1) | E=1 ~ B + x
enf_e1 <- enf_panel[enf_panel$any_enforcement == 1 & !is.na(enf_panel$days_to_RTC), ]
cat(sprintf("E=1 obs with days_to_RTC: %d\n", nrow(enf_e1)))
fit_2b <- feols(
  log(days_to_RTC + 1) ~ B + num_facilities + POPULATION_SERVED_COUNT |
                         OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
  data = enf_e1
)
cat("OLS (Eq. 2b): log(days+1) ~ B + x  (fixed effects: owner, source)\n")
b_xi <- coef(fit_2b)["B"]
b_se <- se(fit_2b)["B"]
cat(sprintf("  xi_B             : %.5f   (t = %.2f)\n\n",
            b_xi, b_xi / b_se))

# Build x-bins from quartiles of IV value in post-95 subsample
post <- panel[panel$post95 == 1, ]
brks <- unique(quantile(post$z[post$z > 0], probs = c(0, 0.25, 0.5, 0.75, 1),
                        na.rm = TRUE))
panel$z_bin <- cut(panel$z, breaks = c(-Inf, brks[-1]),
                   labels = paste0("Q", seq_len(length(brks) - 1)),
                   include.lowest = TRUE)
panel$z_bin <- droplevels(panel$z_bin)
cat("Cross-x-bins: quartiles of z = post95 * sulfur_unified (post-95 distrib.).\n\n")

# Compute Delta_e_hat at the median x of each bin (post-95 only, so v_hat
# is not zeroed out artificially)
make_x_row <- function(sub) {
  data.frame(
    num_facilities          = median(sub$num_facilities, na.rm = TRUE),
    POPULATION_SERVED_COUNT = median(sub$POPULATION_SERVED_COUNT, na.rm = TRUE),
    OWNER_TYPE_CODE     = names(sort(table(sub$OWNER_TYPE_CODE), decreasing = TRUE))[1],
    PRIMARY_SOURCE_CODE = names(sort(table(sub$PRIMARY_SOURCE_CODE), decreasing = TRUE))[1],
    v_hat = median(sub$v_hat, na.rm = TRUE)
  )
}

bin_levels <- levels(panel$z_bin)
delta_e_tbl <- data.frame()
for (b in bin_levels) {
  sub <- panel[panel$z_bin == b & panel$post95 == 1, ]
  if (nrow(sub) == 0) next
  x_row  <- make_x_row(sub)
  # Pr(E=1) at B=0 and B=1
  p0     <- predict(fit_2a, newdata = cbind(B = 0, x_row), type = "response")
  p1     <- predict(fit_2a, newdata = cbind(B = 1, x_row), type = "response")
  # E[days | E=1] at B=0 and B=1
  d0     <- exp(predict(fit_2b, newdata = cbind(B = 0, x_row))) - 1
  d1     <- exp(predict(fit_2b, newdata = cbind(B = 1, x_row))) - 1
  e0     <- p0 * d0
  e1     <- p1 * d1
  delta_e_tbl <- rbind(delta_e_tbl, data.frame(
    z_bin = b, p_E_B0 = p0, p_E_B1 = p1, d_B0 = d0, d_B1 = d1,
    e_B0 = e0, e_B1 = e1, Delta_e = e1 - e0,
    n_obs = nrow(sub)
  ))
}
cat("Reconstructed two-point penalty schedule by IV quartile (medians of x):\n")
delta_e_print <- delta_e_tbl
num_cols <- sapply(delta_e_print, is.numeric)
delta_e_print[num_cols] <- lapply(delta_e_print[num_cols], round, 3)
print(delta_e_print)

de <- delta_e_tbl$Delta_e
cat(sprintf("\nDelta_e across bins: mean=%.2f, sd=%.2f, range=[%.2f, %.2f]\n",
            mean(de), sd(de), min(de), max(de)))
cat(sprintf("Coefficient of variation: %.3f\n", sd(de) / mean(de)))

# Regression: Delta_e_hat at the panel level on z and x
panel$e0_hat <- predict(fit_2a, newdata = cbind(B = 0, panel),
                        type = "response") *
                (exp(predict(fit_2b, newdata = cbind(B = 0, panel))) - 1)
panel$e1_hat <- predict(fit_2a, newdata = cbind(B = 1, panel),
                        type = "response") *
                (exp(predict(fit_2b, newdata = cbind(B = 1, panel))) - 1)
panel$Delta_e_hat <- panel$e1_hat - panel$e0_hat

cat(sprintf("\nDelta_e_hat at panel level (n=%d):\n", nrow(panel)))
cat(sprintf("  mean=%.2f, sd=%.2f, p10=%.2f, p90=%.2f\n",
            mean(panel$Delta_e_hat, na.rm = TRUE),
            sd(panel$Delta_e_hat,   na.rm = TRUE),
            quantile(panel$Delta_e_hat, 0.10, na.rm = TRUE),
            quantile(panel$Delta_e_hat, 0.90, na.rm = TRUE)))

# Variance decomposition: how much of Delta_e_hat variation is explained
# by x (controls + state + year + PWSID FE)?
fit_decomp <- feols(Delta_e_hat ~ z + num_facilities + POPULATION_SERVED_COUNT |
                                 PWSID + year + state,
                    data = panel)
ssr_full   <- sum(residuals(fit_decomp)^2)
ssr_null   <- sum((panel$Delta_e_hat - mean(panel$Delta_e_hat, na.rm = TRUE))^2,
                  na.rm = TRUE)
r2         <- 1 - ssr_full / ssr_null
cat(sprintf("\nR^2 of Delta_e_hat ~ z + x + FE: %.3f\n", r2))

cat("\nVerdict:\n")
if (sd(de) < 1e-6 || is.na(sd(de))) {
  cat("  Delta_e_hat is constant across IV-bins. F(theta|x) is identified at\n")
  cat("  only one point overall; the GMM moment system in Eq. 4 fails.\n")
} else if (sd(de) / mean(de) < 0.05) {
  cat("  Cross-bin variation in Delta_e_hat is small (CV < 5%%).\n")
  cat("  F(theta|x) will be poorly identified. Consider richer x-bin definition.\n")
} else {
  cat("  Delta_e_hat varies meaningfully across IV-bins. GMM identification\n")
  cat("  of F(theta|x) is supported in principle.\n")
}
cat("\n")


# ==========================================================
# CHECK 3: Monotonicity of p_hat(x) in IV
# ==========================================================
cat("----------------------------------------------------------\n")
cat("CHECK 3: Is p_hat(x) = Pr(B=1|x) monotone in the IV?\n")
cat("----------------------------------------------------------\n")

# Raw bin means of B by IV quartile (post-95 obs)
p_raw <- post |>
  mutate(z_bin = cut(z, breaks = c(-Inf, brks[-1]),
                     labels = paste0("Q", seq_len(length(brks) - 1)),
                     include.lowest = TRUE)) |>
  group_by(z_bin) |>
  summarise(p_hat_raw = mean(B), n = n(), .groups = "drop")

# Probit Eq. 3 with control function
fit_3 <- glm(B ~ log(1 + num_coal_mines_upstream) + sulfur_unified +
                 num_facilities + POPULATION_SERVED_COUNT +
                 factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
                 v_hat,
             family = binomial(link = "probit"), data = panel)
panel$p_hat <- predict(fit_3, type = "response")

p_fit <- panel |>
  filter(post95 == 1, !is.na(z_bin)) |>
  group_by(z_bin) |>
  summarise(p_hat_fit = mean(p_hat), n = n(), .groups = "drop")

p_tbl <- merge(p_raw, p_fit, by = "z_bin")
cat("p(x) by IV quartile (post-95 obs):\n")
p_print <- as.data.frame(p_tbl)
num_cols <- sapply(p_print, is.numeric)
p_print[num_cols] <- lapply(p_print[num_cols], round, 4)
print(p_print)

# Monotonicity test: regress p_hat on z_bin index and check sign + significance
post$z_bin_idx <- as.integer(cut(post$z, breaks = c(-Inf, brks[-1]),
                                 include.lowest = TRUE))
mono <- lm(B ~ z_bin_idx, data = post)
mono_coef <- coef(mono)["z_bin_idx"]
mono_se   <- sqrt(diag(vcov(mono)))["z_bin_idx"]
cat(sprintf("\nLinear trend in B across IV quartiles: %.5f  (t=%.2f)\n",
            mono_coef, mono_coef / mono_se))

# Pairwise checks
raw_v <- p_tbl$p_hat_raw
fit_v <- p_tbl$p_hat_fit
cat("\nPairwise increments (raw and fitted p_hat):\n")
for (i in 2:length(raw_v)) {
  cat(sprintf("  %s -> %s : raw delta=%+.4f, fitted delta=%+.4f\n",
              p_tbl$z_bin[i - 1], p_tbl$z_bin[i],
              raw_v[i] - raw_v[i - 1], fit_v[i] - fit_v[i - 1]))
}

n_pos_raw <- sum(diff(raw_v) >= 0)
n_pos_fit <- sum(diff(fit_v) >= 0)
n_inc     <- length(raw_v) - 1
cat(sprintf("\nFraction of increments positive (raw):    %d / %d\n", n_pos_raw, n_inc))
cat(sprintf("Fraction of increments positive (fitted): %d / %d\n", n_pos_fit, n_inc))

# Save figure
dir.create("output/fig", showWarnings = FALSE, recursive = TRUE)
plot_df <- rbind(
  data.frame(z_bin = p_tbl$z_bin, p_hat = p_tbl$p_hat_raw, source = "raw"),
  data.frame(z_bin = p_tbl$z_bin, p_hat = p_tbl$p_hat_fit, source = "fitted (probit)")
)
p <- ggplot(plot_df, aes(x = z_bin, y = p_hat, colour = source, group = source)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  labs(x = "IV quartile (z = post95 * sulfur_unified)",
       y = expression(hat(p)(x) == Pr(B == 1 ~ "|" ~ x)),
       colour = NULL) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())
ggsave("output/fig/binary_feasibility_p_hat_by_iv.png",
       plot = p, width = 6, height = 4, dpi = 200)
cat("\nWrote: output/fig/binary_feasibility_p_hat_by_iv.png\n")

cat("\nVerdict:\n")
if (mono_coef / mono_se < -2) {
  cat("  p_hat(x) is monotonically DECREASING in the IV.\n")
  cat("  Sign is the wrong way around for the standard story; investigate before\n")
  cat("  proceeding to Eq. 4.\n")
} else if (mono_coef / mono_se > 2 && n_pos_raw == n_inc) {
  cat("  p_hat(x) is strictly increasing in the IV; LPV-analogue monotonicity holds.\n")
} else if (n_pos_raw >= n_inc - 1) {
  cat("  p_hat(x) is nearly monotone (one inversion). Likely workable; check\n")
  cat("  whether the inversion is at the same quartile (Q3->Q4) that broke the\n")
  cat("  continuous Check 3.\n")
} else {
  cat("  p_hat(x) is non-monotone. Binary IV-adapted identification is in doubt.\n")
}

cat("\n==========================================================\n")
cat("SUMMARY\n")
cat("==========================================================\n")
cat("Check 1 (Pr(E=1) responds to B): see phi_B above\n")
cat("Check 2 (Cross-bin Delta_e var): see CV above\n")
cat("Check 3 (p_hat monotone in IV) : see trend coef and pairwise above\n")
cat("==========================================================\n")
