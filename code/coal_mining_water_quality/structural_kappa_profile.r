# ============================================================
# Script: structural_kappa_profile.r
# Purpose: Profile pseudo-likelihood (Eq. 4) over κ ∈ {0, 0.2, 0.5, 0.8, 1}
#          to assess identification and find sign-flip point for δ_μ[mining].
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/fig/kappa_profile.png
# Author: EK  Date: 2026-06-01
# ============================================================

suppressPackageStartupMessages({
  library(arrow)
  library(fixest)
  library(dplyr)
  library(data.table)
  library(ggplot2)
})

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

dir.create("output/fig", showWarnings = FALSE, recursive = TRUE)

# Finer grid around the previously estimated sign-flip region (κ ≈ 0.25)
KAPPA_GRID <- c(0, 0.1, 0.2, 0.3, 0.5, 0.8, 1.0)


# ============================================================
# A. LOAD DATA AND CONSTRUCT B_it
# ============================================================
df    <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
df    <- df[df$PWSID != "WV3303401", ]

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

panel$state                   <- panel$STATE_CODE
panel$sulfur_unified          <- panel$sulfur_unified_mean
panel$num_coal_mines_upstream <- panel$num_coal_mines_upstream_mean
panel$z                       <- panel$post95 * panel$sulfur_unified

mining  <- c("nitrates", "arsenic", "inorganic_chemicals", "radionuclides")
mr_vars <- paste0(mining, "_MR_share_days")
panel$B <- as.integer(rowSums(panel[, mr_vars], na.rm = TRUE) > 0)
pwsids  <- unique(panel$PWSID)

cat(sprintf("N obs: %d  PWSIDs: %d  Share B=1: %.2f%%\n",
            nrow(panel), length(pwsids), 100 * mean(panel$B)))


# ============================================================
# B. EQ. 1 — FIRST STAGE
# ============================================================
fit_1 <- feols(
  num_coal_mines_upstream ~ z + num_facilities | PWSID + year + state,
  data = panel, cluster = ~PWSID, fixef.rm = "none"
)
r1 <- residuals(fit_1)
panel$v_hat <- NA_real_
if (length(r1) == nrow(panel)) {
  panel$v_hat <- r1
} else {
  panel$v_hat[as.integer(names(r1))] <- r1
}


# ============================================================
# C. ENFORCEMENT DATA
# ============================================================
enf_path <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv"
enf_raw  <- fread(enf_path,
                  select     = c("PWSID", "COMPL_PER_BEGIN_DATE",
                                 "ENF_ACTION_CATEGORY", "CALCULATED_RTC_DATE"),
                  colClasses = "character")
enf_raw[, year := as.integer(substr(COMPL_PER_BEGIN_DATE, 7, 10))]
enf <- enf_raw[PWSID %in% pwsids & year >= 1985 & year <= 2005]

formal_py   <- enf[ENF_ACTION_CATEGORY == "Formal",
                    .(formal_enf = 1L), by = .(PWSID, year)]
informal_py <- enf[ENF_ACTION_CATEGORY == "Informal",
                    .(informal_enf = 1L), by = .(PWSID, year)]
panel <- merge(panel, formal_py,   by = c("PWSID", "year"), all.x = TRUE)
panel <- merge(panel, informal_py, by = c("PWSID", "year"), all.x = TRUE)
panel$formal_enf   <- ifelse(is.na(panel$formal_enf),   0L, 1L)
panel$informal_enf <- ifelse(is.na(panel$informal_enf), 0L, 1L)

enf[, viol_date   := as.Date(COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
enf[, rtc_date    := as.Date(CALCULATED_RTC_DATE,  format = "%m/%d/%Y")]
enf[, days_to_rtc := as.numeric(rtc_date - viol_date)]
enf_valid <- enf[!is.na(days_to_rtc) & days_to_rtc >= 0 & days_to_rtc <= 3650]

rtc_formal   <- enf_valid[ENF_ACTION_CATEGORY == "Formal",
                            .(days_to_RTC_formal = median(days_to_rtc)), by = .(PWSID, year)]
rtc_informal <- enf_valid[ENF_ACTION_CATEGORY == "Informal",
                            .(days_to_RTC_informal = median(days_to_rtc)), by = .(PWSID, year)]
panel <- merge(panel, rtc_formal,   by = c("PWSID", "year"), all.x = TRUE)
panel <- merge(panel, rtc_informal, by = c("PWSID", "year"), all.x = TRUE)

formal_pwsids   <- unique(enf[ENF_ACTION_CATEGORY == "Formal",   PWSID])
informal_pwsids <- unique(enf[ENF_ACTION_CATEGORY == "Informal", PWSID])
formal_enf_panel   <- panel[panel$PWSID %in% formal_pwsids, ]
informal_enf_panel <- panel[panel$PWSID %in% informal_pwsids, ]

# any_snsv
snsv_path  <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv"
snsv_codes <- c("SNSV", "SNSP", "L1SS", "L2SS", "SSVF")
panel$any_snsv <- 0L
if (file.exists(snsv_path)) {
  snsv_raw   <- fread(snsv_path, colClasses = "character")
  date_col   <- intersect(c("VISIT_DATE", "SITE_VISIT_DATE", "COMPL_PER_BEGIN_DATE",
                             "ACTIVITY_START_DATE"), names(snsv_raw))[1]
  reason_col <- intersect(c("VISIT_REASON_CODE", "ACTIVITY_TYPE_CODE"), names(snsv_raw))[1]
  if (!is.na(date_col) && !is.na(reason_col)) {
    snsv_raw[, snsv_year := as.integer(substr(get(date_col), 7, 10))]
    snsv_sub <- snsv_raw[get(reason_col) %in% snsv_codes & PWSID %in% pwsids &
                           !is.na(snsv_year) & snsv_year >= 1985 & snsv_year <= 2005]
    snsv_py <- snsv_sub[, .(any_snsv = 1L), by = .(PWSID, year = snsv_year)]
    panel$any_snsv <- NULL
    panel <- merge(panel, snsv_py, by = c("PWSID", "year"), all.x = TRUE)
    panel$any_snsv <- ifelse(is.na(panel$any_snsv), 0L, panel$any_snsv)
  }
}
formal_enf_panel   <- panel[panel$PWSID %in% formal_pwsids, ]
informal_enf_panel <- panel[panel$PWSID %in% informal_pwsids, ]


# ============================================================
# D. EQS. 2a + 2b — ENFORCEMENT SCHEDULE
# ============================================================
owner_lvl_f   <- levels(factor(formal_enf_panel$OWNER_TYPE_CODE))
source_lvl_f  <- levels(factor(formal_enf_panel$PRIMARY_SOURCE_CODE))
state_lvl_f   <- levels(factor(formal_enf_panel$state))
modal_owner_f <- names(sort(table(formal_enf_panel$OWNER_TYPE_CODE),  decreasing=TRUE))[1]
modal_src_f   <- names(sort(table(formal_enf_panel$PRIMARY_SOURCE_CODE), decreasing=TRUE))[1]
modal_state_f <- names(sort(table(formal_enf_panel$state), decreasing=TRUE))[1]

fit_2a_formal <- glm(
  formal_enf ~ B + log(1 + num_coal_mines_upstream) +
    num_facilities + POPULATION_SERVED_COUNT +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + factor(state) + v_hat,
  family = binomial("probit"), data = formal_enf_panel
)

owner_lvl_i   <- levels(factor(informal_enf_panel$OWNER_TYPE_CODE))
source_lvl_i  <- levels(factor(informal_enf_panel$PRIMARY_SOURCE_CODE))
state_lvl_i   <- levels(factor(informal_enf_panel$state))
modal_owner_i <- names(sort(table(informal_enf_panel$OWNER_TYPE_CODE),  decreasing=TRUE))[1]
modal_src_i   <- names(sort(table(informal_enf_panel$PRIMARY_SOURCE_CODE), decreasing=TRUE))[1]
modal_state_i <- names(sort(table(informal_enf_panel$state), decreasing=TRUE))[1]

fit_2a_informal <- glm(
  informal_enf ~ B + log(1 + num_coal_mines_upstream) +
    num_facilities + POPULATION_SERVED_COUNT +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + factor(state) + v_hat,
  family = binomial("probit"), data = informal_enf_panel
)

formal_e1 <- panel[panel$formal_enf == 1 & !is.na(panel$days_to_RTC_formal), ]
fit_2b_formal <- feols(
  log(days_to_RTC_formal + 1) ~ B + log(1 + num_coal_mines_upstream) +
    num_facilities + POPULATION_SERVED_COUNT + factor(state) | OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
  data = formal_e1
)

informal_e1 <- panel[panel$informal_enf == 1 & panel$formal_enf == 0 &
                       !is.na(panel$days_to_RTC_informal), ]
fit_2b_informal <- feols(
  log(days_to_RTC_informal + 1) ~ B + log(1 + num_coal_mines_upstream) +
    num_facilities + POPULATION_SERVED_COUNT + factor(state) | OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
  data = informal_e1
)

# Predict Δê_formal and Δê_informal at full panel level
panel_pred_f <- panel
panel_pred_f$OWNER_TYPE_CODE[!panel_pred_f$OWNER_TYPE_CODE %in% owner_lvl_f] <- modal_owner_f
panel_pred_f$PRIMARY_SOURCE_CODE[!panel_pred_f$PRIMARY_SOURCE_CODE %in% source_lvl_f] <- modal_src_f
state_safe_f     <- intersect(state_lvl_f, levels(factor(formal_e1$state)))
modal_state_f_2b <- names(sort(table(formal_e1$state), decreasing = TRUE))[1]
panel_pred_f$state[!panel_pred_f$state %in% state_safe_f] <- modal_state_f_2b

panel_pred_i <- panel
panel_pred_i$OWNER_TYPE_CODE[!panel_pred_i$OWNER_TYPE_CODE %in% owner_lvl_i] <- modal_owner_i
panel_pred_i$PRIMARY_SOURCE_CODE[!panel_pred_i$PRIMARY_SOURCE_CODE %in% source_lvl_i] <- modal_src_i
state_safe_i     <- intersect(state_lvl_i, levels(factor(informal_e1$state)))
modal_state_i_2b <- names(sort(table(informal_e1$state), decreasing = TRUE))[1]
panel_pred_i$state[!panel_pred_i$state %in% state_safe_i] <- modal_state_i_2b

pf_B0 <- predict(fit_2a_formal,   newdata=cbind(B=0L, panel_pred_f), type="response")
pf_B1 <- predict(fit_2a_formal,   newdata=cbind(B=1L, panel_pred_f), type="response")
df_B0 <- exp(predict(fit_2b_formal,   newdata=cbind(B=0L, panel_pred_f))) - 1
df_B1 <- exp(predict(fit_2b_formal,   newdata=cbind(B=1L, panel_pred_f))) - 1
panel$Delta_e_formal <- pmax(pf_B1*pmax(df_B1,0) - pf_B0*pmax(df_B0,0), 1e-6)

pi_B0 <- predict(fit_2a_informal, newdata=cbind(B=0L, panel_pred_i), type="response")
pi_B1 <- predict(fit_2a_informal, newdata=cbind(B=1L, panel_pred_i), type="response")
di_B0 <- exp(predict(fit_2b_informal, newdata=cbind(B=0L, panel_pred_i))) - 1
di_B1 <- exp(predict(fit_2b_informal, newdata=cbind(B=1L, panel_pred_i))) - 1
panel$Delta_e_informal <- pmax(pi_B1*pmax(di_B1,0) - pi_B0*pmax(di_B0,0), 1e-6)

# Floor Delta_e_formal at its 5th percentile to prevent extreme ratio outliers.
# Observations with near-zero formal enforcement (Δê_formal ≈ 1e-6) make the ratio
# Δê_informal / Δê_formal enormous and destabilise the κ-gradient.
p05_formal <- quantile(panel$Delta_e_formal, 0.05, na.rm = TRUE)
panel$Delta_e_formal <- pmax(panel$Delta_e_formal, p05_formal)
cat(sprintf("Floor Delta_e_formal at p05 = %.2f days\n", p05_formal))

cat(sprintf("Δê_formal:   mean=%.1f sd=%.1f  cor(mining,Δê_f)=%.3f\n",
            mean(panel$Delta_e_formal), sd(panel$Delta_e_formal),
            cor(panel$num_coal_mines_upstream, panel$Delta_e_formal, use="complete.obs")))
cat(sprintf("Δê_informal: mean=%.1f sd=%.1f  cor(mining,Δê_i)=%.3f\n",
            mean(panel$Delta_e_informal), sd(panel$Delta_e_informal),
            cor(panel$num_coal_mines_upstream, panel$Delta_e_informal, use="complete.obs")))
cat(sprintf("ratio Δê_i/Δê_f: mean=%.2f sd=%.2f  (after floor)\n",
            mean(panel$Delta_e_informal / panel$Delta_e_formal),
            sd(panel$Delta_e_informal   / panel$Delta_e_formal)))


# ============================================================
# E. BUILD W ONCE (shared across κ values)
# ============================================================
# Complete-case mask uses a placeholder log_delta_e; recomputed per κ
cc_vars_base <- c("num_coal_mines_upstream", "sulfur_unified", "num_facilities",
                  "POPULATION_SERVED_COUNT", "OWNER_TYPE_CODE", "PRIMARY_SOURCE_CODE",
                  "any_snsv", "v_hat", "B",
                  "Delta_e_formal", "Delta_e_informal")
cc_mask  <- complete.cases(panel[, cc_vars_base])
panel_cc <- panel[cc_mask, ]
cat(sprintf("Complete cases: %d / %d\n", nrow(panel_cc), nrow(panel)))

W <- model.matrix(
  ~ log(1 + num_coal_mines_upstream) + sulfur_unified +
    num_facilities + log(POPULATION_SERVED_COUNT + 1) +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
    any_snsv + v_hat,
  data = panel_cc
)
K       <- ncol(W)
W_names <- colnames(W)
B_cc    <- panel_cc$B

# Index of mining coefficient in W
mining_idx <- grep("num_coal_mines_upstream", W_names)[1]
cat(sprintf("W: %d obs x %d cols; mining col = '%s' (index %d)\n",
            nrow(W), K, W_names[mining_idx], mining_idx))

# ── Pseudo-likelihood function (given log_delta_e vector) ────────────────────
fit_eq4 <- function(log_delta_e_vec, start = NULL) {
  if (is.null(start)) {
    s_mu    <- rep(0, K)
    s_mu[1] <- mean(log_delta_e_vec) - qnorm(1 - mean(B_cc))
    start   <- c(s_mu, rep(0, K))
  }
  loglik <- function(par) {
    dmu <- par[1:K]; dsi <- par[(K+1):(2*K)]
    mu  <- as.numeric(W %*% dmu)
    sig <- exp(as.numeric(W %*% dsi))
    eta <- (log_delta_e_vec - mu) / sig
    p1  <- pmin(pmax(pnorm(eta, lower.tail=FALSE), 1e-12), 1-1e-12)
    -sum(B_cc * log(p1) + (1 - B_cc) * log(1 - p1))
  }
  nlminb(start, loglik, control = list(iter.max = 3000, eval.max = 6000))
}


# ============================================================
# F. PROFILE OVER κ GRID — SEQUENTIAL WARM STARTS
#    Each κ is initialized from the previous κ's converged solution.
#    This traces a connected path through parameter space instead of
#    starting cold each time, preventing the optimizer from landing on
#    different local optima at each grid point.
# ============================================================
cat("\n--- Profiling Eq. 4 over kappa grid (warm starts) ---\n")
cat(sprintf("%-8s  %-12s  %-14s  %-6s\n",
            "kappa", "log-lik", "delta_mu[mining]", "status"))

results  <- vector("list", length(KAPPA_GRID))
prev_par <- NULL   # warm-start seed; NULL → use default heuristic at κ=0

for (idx in seq_along(KAPPA_GRID)) {
  kap <- KAPPA_GRID[idx]

  Delta_e_kap <- panel_cc$Delta_e_formal + kap * panel_cc$Delta_e_informal
  log_delta_e <- log(pmax(Delta_e_kap, 1e-6))

  fit <- fit_eq4(log_delta_e, start = prev_par)

  # If warm start converged worse than cold start, try cold start too
  if (!is.null(prev_par)) {
    fit_cold <- fit_eq4(log_delta_e, start = NULL)
    if (fit_cold$objective < fit$objective) {
      fit <- fit_cold
    }
  }

  loglik_val   <- -fit$objective
  delta_mu_hat <- fit$par[1:K]
  dm_mining    <- delta_mu_hat[mining_idx]
  status       <- fit$convergence

  cat(sprintf("kappa=%-4g  loglik=%12.2f  delta_mu[mining]=%+.4f  status=%d\n",
              kap, loglik_val, dm_mining, status))

  results[[idx]] <- list(kappa        = kap,
                         loglik       = loglik_val,
                         dm_mining    = dm_mining,
                         status       = status,
                         delta_mu_hat = delta_mu_hat,
                         par          = fit$par)
  prev_par <- fit$par   # seed next iteration
}

res_df <- data.frame(
  kappa     = sapply(results, `[[`, "kappa"),
  loglik    = sapply(results, `[[`, "loglik"),
  dm_mining = sapply(results, `[[`, "dm_mining"),
  status    = sapply(results, `[[`, "status")
)

cat("\n--- Profile summary ---\n")
print(res_df)

loglik_range <- diff(range(res_df$loglik))
cat(sprintf("\nLog-lik range across grid: %.2f units\n", loglik_range))
if (loglik_range < 2) {
  cat("  => Likelihood nearly flat in kappa (< 2 units): kappa is weakly identified.\n")
} else {
  cat("  => Likelihood has curvature in kappa: kappa carries identification content.\n")
}


# ============================================================
# G. PLOT
# ============================================================
# Normalise log-lik relative to κ=0
res_df$loglik_rel <- res_df$loglik - res_df$loglik[res_df$kappa == 0]

# Sign-flip κ (linear interpolation)
sign_flip_kappa <- NA_real_
if (any(res_df$dm_mining > 0) && any(res_df$dm_mining < 0)) {
  # find adjacent pair where sign changes
  for (i in seq_len(nrow(res_df) - 1)) {
    if (res_df$dm_mining[i] * res_df$dm_mining[i+1] < 0) {
      k0 <- res_df$kappa[i];    d0 <- res_df$dm_mining[i]
      k1 <- res_df$kappa[i+1];  d1 <- res_df$dm_mining[i+1]
      sign_flip_kappa <- k0 - d0 * (k1 - k0) / (d1 - d0)
      break
    }
  }
  cat(sprintf("\nSign-flip kappa (linear interp): %.3f\n", sign_flip_kappa))
} else {
  cat("\nNo sign flip within kappa grid.\n")
}

# Panel 1: log-lik
p1 <- ggplot(res_df, aes(x = kappa, y = loglik_rel)) +
  geom_line(colour = "steelblue", linewidth = 1) +
  geom_point(colour = "steelblue", size = 3) +
  geom_hline(yintercept = -2, linetype = "dashed", colour = "grey50") +
  annotate("text", x = max(KAPPA_GRID) * 0.98, y = -2.2,
           label = "−2 log-lik", hjust = 1, size = 3, colour = "grey40") +
  scale_x_continuous(breaks = KAPPA_GRID) +
  labs(x = NULL,
       y = expression(paste(Delta, " log-lik vs ", kappa == 0)),
       title = "A: Profile log-likelihood") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

# Panel 2: δ_μ[mining]
p2_base <- ggplot(res_df, aes(x = kappa, y = dm_mining)) +
  geom_hline(yintercept = 0, linetype = "solid", colour = "grey30", linewidth = 0.5) +
  geom_line(colour = "tomato", linewidth = 1) +
  geom_point(colour = "tomato", size = 3) +
  scale_x_continuous(breaks = KAPPA_GRID) +
  labs(x = expression(kappa ~ "(informal enforcement weight)"),
       y = expression(delta[mu] * "[mining]"),
       title = expression(paste("B: ", delta[mu], "[mining] vs ", kappa,
                                "  (+ = higher compliance cost in mining areas)"))) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

if (!is.na(sign_flip_kappa)) {
  p2_base <- p2_base +
    geom_vline(xintercept = sign_flip_kappa, linetype = "dotted", colour = "grey50") +
    annotate("text", x = sign_flip_kappa + 0.02, y = max(res_df$dm_mining) * 0.9,
             label = sprintf("sign flip\nκ ≈ %.2f", sign_flip_kappa),
             hjust = 0, size = 3, colour = "grey40")
}
p2 <- p2_base

# Combine and save
combined <- ggplot() + theme_void()  # spacer
library(grid)
png("output/fig/kappa_profile.png", width = 7, height = 6, units = "in", res = 200)
grid.newpage()
pushViewport(viewport(layout = grid.layout(2, 1)))
print(p1, vp = viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = viewport(layout.pos.row = 2, layout.pos.col = 1))
dev.off()
cat("\nWrote: output/fig/kappa_profile.png\n")

cat("\n==========================================================\n")
cat("DONE — kappa profile complete.\n")
cat("==========================================================\n")
