# ============================================================
# Script: structural_ks_binary.r
# Purpose: K&S-adapted static structural model, binary firm action
#          Eqs. 1-7 + CFs per 2026-05-22 proposal (§7, updated §16 and §17)
#          Formal/informal enforcement split (§17); any_snsv in W.
#          Option C pseudo-likelihood for Eq. 4 (primary);
#          observation-level NLS for Eq. 5; 500-rep PWSID cluster bootstrap.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/struct/primitives_binary.rds
#          output/reg/structural_eq7.tex
#          output/fig/binary_counterfactuals.png
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

# Number of bootstrap replications.  Set to 0 to skip bootstrap.
N_BOOT <- 0

# ── Utility: wrap etable .tex for beamer + regular LaTeX ─────────────────────
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

# ── Utility: solve regulator FOC for θ* given (γ, ψ, F, f) ──────────────────
# Used in counterfactuals.  Returns NA on failure.
solve_theta_star <- function(gamma_i, psi_i, mu_i, sigma_i,
                             lower = 1e-6, upper = 5e3) {
  obj <- function(theta) {
    F_val <- plnorm(theta, mu_i, sigma_i)
    f_val <- dlnorm(theta, mu_i, sigma_i)
    gamma_i - theta * (1 + psi_i) - psi_i * (1 - F_val) / max(f_val, 1e-14)
  }
  tryCatch(uniroot(obj, c(lower, upper), tol = 1e-8)$root,
           error = function(e) NA_real_)
}


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

# Aliases to match proposal notation
panel$state                   <- panel$STATE_CODE
panel$sulfur_unified          <- panel$sulfur_unified_mean
panel$num_coal_mines_upstream <- panel$num_coal_mines_upstream_mean
panel$z                       <- panel$post95 * panel$sulfur_unified

# Binary firm action: any MR violation day across mining-related contaminants
mining  <- c("nitrates", "arsenic", "inorganic_chemicals", "radionuclides")
mr_vars <- paste0(mining, "_MR_share_days")
panel$B <- as.integer(rowSums(panel[, mr_vars], na.rm = TRUE) > 0)

pwsids <- unique(panel$PWSID)

cat("==========================================================\n")
cat("STRUCTURAL K&S BINARY — ESTIMATION\n")
cat(sprintf("N obs: %d   N unique PWSIDs: %d   Share B=1: %.2f%%\n\n",
            nrow(panel), length(pwsids), 100 * mean(panel$B)))


# ============================================================
# B. EQ. 1 — FIRST STAGE / CONTROL FUNCTION
# ============================================================
cat("-- Eq. 1: First stage\n")

fit_1 <- feols(
  num_coal_mines_upstream ~ z + num_facilities | PWSID + year + state,
  data     = panel,
  cluster  = ~PWSID,
  fixef.rm = "none"
)
w_z   <- suppressMessages(capture.output(w_test <- wald(fit_1, "z")))
f_1st <- w_test$stat
cat(sprintf("  First-stage F (z = post95*sulfur) = %.1f\n", f_1st))

# Align residuals robustly (feols may drop singletons)
r1 <- residuals(fit_1)
panel$v_hat <- NA_real_
if (length(r1) == nrow(panel)) {
  panel$v_hat <- r1
} else {
  keep_idx <- as.integer(names(r1))
  panel$v_hat[keep_idx] <- r1
}


# ============================================================
# C. ENFORCEMENT DATA — LOAD, MERGE, CONSTRUCT INDICATORS
# ============================================================
cat("-- Loading enforcement data\n")

enf_path <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv"
enf_raw  <- fread(enf_path,
                  select     = c("PWSID", "COMPL_PER_BEGIN_DATE",
                                 "ENF_ACTION_CATEGORY", "CALCULATED_RTC_DATE"),
                  colClasses = "character")
enf_raw[, year := as.integer(substr(COMPL_PER_BEGIN_DATE, 7, 10))]
enf <- enf_raw[PWSID %in% pwsids & year >= 1985 & year <= 2005]

# ---- Per-type annual indicators ----
formal_py   <- enf[ENF_ACTION_CATEGORY == "Formal",
                    .(formal_enf = 1L), by = .(PWSID, year)]
informal_py <- enf[ENF_ACTION_CATEGORY == "Informal",
                    .(informal_enf = 1L), by = .(PWSID, year)]

panel <- merge(panel, formal_py,   by = c("PWSID", "year"), all.x = TRUE)
panel <- merge(panel, informal_py, by = c("PWSID", "year"), all.x = TRUE)
panel$formal_enf      <- ifelse(is.na(panel$formal_enf),   0L, 1L)
panel$informal_enf    <- ifelse(is.na(panel$informal_enf), 0L, 1L)
panel$any_enforcement <- pmax(panel$formal_enf, panel$informal_enf)

# ---- Days-to-RTC by enforcement type ----
enf[, viol_date   := as.Date(COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
enf[, rtc_date    := as.Date(CALCULATED_RTC_DATE,  format = "%m/%d/%Y")]
enf[, days_to_rtc := as.numeric(rtc_date - viol_date)]
enf_valid <- enf[!is.na(days_to_rtc) & days_to_rtc >= 0 & days_to_rtc <= 3650]

rtc_formal   <- enf_valid[ENF_ACTION_CATEGORY == "Formal",
                            .(days_to_RTC_formal = median(days_to_rtc, na.rm = TRUE)),
                            by = .(PWSID, year)]
rtc_informal <- enf_valid[ENF_ACTION_CATEGORY == "Informal",
                            .(days_to_RTC_informal = median(days_to_rtc, na.rm = TRUE)),
                            by = .(PWSID, year)]
rtc_annual   <- enf_valid[, .(days_to_RTC = median(days_to_rtc, na.rm = TRUE)),
                            by = .(PWSID, year)]

panel <- merge(panel, rtc_formal,   by = c("PWSID", "year"), all.x = TRUE)
panel <- merge(panel, rtc_informal, by = c("PWSID", "year"), all.x = TRUE)
panel <- merge(panel, rtc_annual,   by = c("PWSID", "year"), all.x = TRUE)

# ---- Enforcement panel subsets ----
formal_pwsids   <- unique(enf[ENF_ACTION_CATEGORY == "Formal",   PWSID])
informal_pwsids <- unique(enf[ENF_ACTION_CATEGORY == "Informal", PWSID])
enf_pwsids      <- union(formal_pwsids, informal_pwsids)

formal_enf_panel   <- panel[panel$PWSID %in% formal_pwsids, ]
informal_enf_panel <- panel[panel$PWSID %in% informal_pwsids, ]

cat(sprintf("  Formal:   %d PWSIDs, %d obs; Pr(formal_enf=1)=%.3f\n",
            length(formal_pwsids), nrow(formal_enf_panel),
            mean(formal_enf_panel$formal_enf)))
cat(sprintf("  Informal: %d PWSIDs, %d obs; Pr(informal_enf=1)=%.3f\n",
            length(informal_pwsids), nrow(informal_enf_panel),
            mean(informal_enf_panel$informal_enf)))

# ---- any_snsv from SDWA_SITE_VISITS.csv ----
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
    snsv_sub <- snsv_raw[get(reason_col) %in% snsv_codes &
                           PWSID %in% pwsids &
                           !is.na(snsv_year) & snsv_year >= 1985 & snsv_year <= 2005]
    snsv_py <- snsv_sub[, .(any_snsv = 1L), by = .(PWSID, year = snsv_year)]
    panel$any_snsv <- NULL
    panel <- merge(panel, snsv_py, by = c("PWSID", "year"), all.x = TRUE)
    panel$any_snsv <- ifelse(is.na(panel$any_snsv), 0L, panel$any_snsv)
    cat(sprintf("  any_snsv: %d PWSID-years with sanitary survey\n",
                sum(panel$any_snsv == 1, na.rm = TRUE)))
  } else {
    cat(sprintf("  WARNING: SDWA_SITE_VISITS.csv columns not recognized (found: %s); any_snsv=0\n",
                paste(names(snsv_raw)[seq_len(min(5L, ncol(snsv_raw)))], collapse = ", ")))
  }
} else {
  cat("  WARNING: SDWA_SITE_VISITS.csv not found; any_snsv=0\n")
}

# Re-derive enforcement panel subsets after panel augmentation
formal_enf_panel   <- panel[panel$PWSID %in% formal_pwsids, ]
informal_enf_panel <- panel[panel$PWSID %in% informal_pwsids, ]


# ============================================================
# D. EQS. 2a + 2b — ENFORCEMENT SCHEDULE (FORMAL / INFORMAL SPLIT)
#    Mining enters all four equations so Δê varies with mining exposure.
#    Primary spec: κ=0 (formal-only).  Robustness: κ free in pseudo-likelihood.
# ============================================================
cat("-- Eq. 2a_formal: probit Pr(formal_enf=1 | B, m, x)\n")

owner_lvl_f   <- levels(factor(formal_enf_panel$OWNER_TYPE_CODE))
source_lvl_f  <- levels(factor(formal_enf_panel$PRIMARY_SOURCE_CODE))
modal_owner_f <- names(sort(table(formal_enf_panel$OWNER_TYPE_CODE),  decreasing = TRUE))[1]
modal_src_f   <- names(sort(table(formal_enf_panel$PRIMARY_SOURCE_CODE), decreasing = TRUE))[1]

fit_2a_formal <- glm(
  formal_enf ~ B + log(1 + num_coal_mines_upstream) +
    num_facilities + POPULATION_SERVED_COUNT +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + v_hat,
  family = binomial(link = "probit"),
  data   = formal_enf_panel
)
phi_B_f <- coef(fit_2a_formal)["B"]
phi_m_f <- coef(fit_2a_formal)["log(1 + num_coal_mines_upstream)"]
se_2af  <- sqrt(diag(vcov(fit_2a_formal)))
cat(sprintf("  phi_B_formal = %.4f (t=%.2f)  phi_m_formal = %.4f (t=%.2f)\n",
            phi_B_f, phi_B_f / se_2af["B"],
            phi_m_f, phi_m_f / se_2af["log(1 + num_coal_mines_upstream)"]))
cat(sprintf("  EJ check: phi_m_formal < 0 => formal enforcement laxity in mining areas: %s\n",
            ifelse(phi_m_f < 0, "YES (expected)", "NO — check")))

cat("-- Eq. 2a_informal: probit Pr(informal_enf=1 | B, m, x)\n")

owner_lvl_i   <- levels(factor(informal_enf_panel$OWNER_TYPE_CODE))
source_lvl_i  <- levels(factor(informal_enf_panel$PRIMARY_SOURCE_CODE))
modal_owner_i <- names(sort(table(informal_enf_panel$OWNER_TYPE_CODE),  decreasing = TRUE))[1]
modal_src_i   <- names(sort(table(informal_enf_panel$PRIMARY_SOURCE_CODE), decreasing = TRUE))[1]

fit_2a_informal <- glm(
  informal_enf ~ B + log(1 + num_coal_mines_upstream) +
    num_facilities + POPULATION_SERVED_COUNT +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + v_hat,
  family = binomial(link = "probit"),
  data   = informal_enf_panel
)
phi_B_i <- coef(fit_2a_informal)["B"]
phi_m_i <- coef(fit_2a_informal)["log(1 + num_coal_mines_upstream)"]
se_2ai  <- sqrt(diag(vcov(fit_2a_informal)))
cat(sprintf("  phi_B_informal = %.4f (t=%.2f)  phi_m_informal = %.4f (t=%.2f)\n",
            phi_B_i, phi_B_i / se_2ai["B"],
            phi_m_i, phi_m_i / se_2ai["log(1 + num_coal_mines_upstream)"]))

cat("-- Eq. 2b_formal: log(days_to_RTC_formal+1) | formal_enf=1\n")
formal_e1 <- panel[panel$formal_enf == 1 & !is.na(panel$days_to_RTC_formal), ]
cat(sprintf("  formal_e1 subsample: %d obs\n", nrow(formal_e1)))

fit_2b_formal <- feols(
  log(days_to_RTC_formal + 1) ~ B + log(1 + num_coal_mines_upstream) +
    num_facilities + POPULATION_SERVED_COUNT |
    OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
  data = formal_e1
)
xi_B_f  <- coef(fit_2b_formal)["B"]
xi_m_f  <- coef(fit_2b_formal)["log(1 + num_coal_mines_upstream)"]
xi_se_f <- se(fit_2b_formal)
cat(sprintf("  xi_B_formal = %.4f (t=%.2f)  xi_m_formal = %.4f (t=%.2f)\n",
            xi_B_f, xi_B_f / xi_se_f["B"],
            xi_m_f, xi_m_f / xi_se_f["log(1 + num_coal_mines_upstream)"]))

cat("-- Eq. 2b_informal: log(days_to_RTC_informal+1) | informal_enf=1 & formal_enf=0\n")
informal_e1 <- panel[panel$informal_enf == 1 & panel$formal_enf == 0 &
                       !is.na(panel$days_to_RTC_informal), ]
cat(sprintf("  informal_e1 subsample: %d obs\n", nrow(informal_e1)))

fit_2b_informal <- feols(
  log(days_to_RTC_informal + 1) ~ B + log(1 + num_coal_mines_upstream) +
    num_facilities + POPULATION_SERVED_COUNT |
    OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
  data = informal_e1
)
xi_B_i  <- coef(fit_2b_informal)["B"]
xi_m_i  <- coef(fit_2b_informal)["log(1 + num_coal_mines_upstream)"]
xi_se_i <- se(fit_2b_informal)
cat(sprintf("  xi_B_informal = %.4f (t=%.2f)  xi_m_informal = %.4f (t=%.2f)\n",
            xi_B_i, xi_B_i / xi_se_i["B"],
            xi_m_i, xi_m_i / xi_se_i["log(1 + num_coal_mines_upstream)"]))

# ── Construct Δê_formal(x), Δê_informal(x) at full panel level ───────────────
panel_pred_f <- panel
panel_pred_f$OWNER_TYPE_CODE[!panel_pred_f$OWNER_TYPE_CODE %in% owner_lvl_f] <- modal_owner_f
panel_pred_f$PRIMARY_SOURCE_CODE[!panel_pred_f$PRIMARY_SOURCE_CODE %in% source_lvl_f] <- modal_src_f

panel_pred_i <- panel
panel_pred_i$OWNER_TYPE_CODE[!panel_pred_i$OWNER_TYPE_CODE %in% owner_lvl_i] <- modal_owner_i
panel_pred_i$PRIMARY_SOURCE_CODE[!panel_pred_i$PRIMARY_SOURCE_CODE %in% source_lvl_i] <- modal_src_i

# Formal two-point schedule
pf_B0 <- predict(fit_2a_formal, newdata = cbind(B = 0L, panel_pred_f), type = "response")
pf_B1 <- predict(fit_2a_formal, newdata = cbind(B = 1L, panel_pred_f), type = "response")
df_B0 <- exp(predict(fit_2b_formal, newdata = cbind(B = 0L, panel_pred_f))) - 1
df_B1 <- exp(predict(fit_2b_formal, newdata = cbind(B = 1L, panel_pred_f))) - 1

panel$e_formal_B0    <- pf_B0 * pmax(df_B0, 0)
panel$e_formal_B1    <- pf_B1 * pmax(df_B1, 0)
panel$Delta_e_formal <- pmax(panel$e_formal_B1 - panel$e_formal_B0, 1e-6)

# Informal two-point schedule
pi_B0 <- predict(fit_2a_informal, newdata = cbind(B = 0L, panel_pred_i), type = "response")
pi_B1 <- predict(fit_2a_informal, newdata = cbind(B = 1L, panel_pred_i), type = "response")
di_B0 <- exp(predict(fit_2b_informal, newdata = cbind(B = 0L, panel_pred_i))) - 1
di_B1 <- exp(predict(fit_2b_informal, newdata = cbind(B = 1L, panel_pred_i))) - 1

panel$e_informal_B0    <- pi_B0 * pmax(di_B0, 0)
panel$e_informal_B1    <- pi_B1 * pmax(di_B1, 0)
panel$Delta_e_informal <- pmax(panel$e_informal_B1 - panel$e_informal_B0, 1e-6)

# Primary spec: κ=0 (formal-only threshold θ*(x) = Δê_formal)
kappa             <- 0
panel$Delta_e     <- panel$Delta_e_formal + kappa * panel$Delta_e_informal
panel$log_delta_e <- log(panel$Delta_e)

cat(sprintf("  Δê_formal:   mean=%.1f  sd=%.1f  p10=%.1f  p90=%.1f days\n",
            mean(panel$Delta_e_formal,   na.rm = TRUE), sd(panel$Delta_e_formal, na.rm = TRUE),
            quantile(panel$Delta_e_formal, 0.10, na.rm = TRUE),
            quantile(panel$Delta_e_formal, 0.90, na.rm = TRUE)))
cat(sprintf("  Δê_informal: mean=%.1f  sd=%.1f  p10=%.1f  p90=%.1f days\n",
            mean(panel$Delta_e_informal, na.rm = TRUE), sd(panel$Delta_e_informal, na.rm = TRUE),
            quantile(panel$Delta_e_informal, 0.10, na.rm = TRUE),
            quantile(panel$Delta_e_informal, 0.90, na.rm = TRUE)))
cat(sprintf("  Δê (κ=%g):   mean=%.1f  sd=%.1f  p10=%.1f  p90=%.1f days\n",
            kappa,
            mean(panel$Delta_e,   na.rm = TRUE), sd(panel$Delta_e, na.rm = TRUE),
            quantile(panel$Delta_e, 0.10, na.rm = TRUE),
            quantile(panel$Delta_e, 0.90, na.rm = TRUE)))
cat(sprintf("  EJ check: cor(mines_upstream, Delta_e_formal) = %.3f  (expected < 0)\n",
            cor(panel$num_coal_mines_upstream, panel$Delta_e_formal, use = "complete.obs")))


# ============================================================
# E. EQ. 3 (DIAGNOSTIC ONLY) — p_hat(x)
#    Retained for: (i) §16 Check 3 monotonicity, (ii) Option B robustness,
#    (iii) post-estimation fit check 1-F̂(Δê|x) vs p̂(x).
#    NOT on the main estimation path for F(·|x).
# ============================================================
cat("-- Eq. 3 (diagnostic): probit p_hat(x)\n")

fit_3 <- glm(
  B ~ log(1 + num_coal_mines_upstream) + sulfur_unified +
    num_facilities + POPULATION_SERVED_COUNT +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
    factor(state) + any_snsv + v_hat,
  family = binomial(link = "probit"),
  data   = panel
)
panel$p_hat_eq3 <- predict(fit_3, type = "response")


# ============================================================
# F. EQ. 4 — F(θ|x) VIA PSEUDO-LIKELIHOOD (OPTION C, PRIMARY)
#    Probit with log(Δê_formal) as known offset; w_it → μ(x) and log σ(x).
#    W now includes any_snsv (monitoring intensity covariate per §17).
# ============================================================
cat("-- Eq. 4: pseudo-likelihood MLE for F(theta|x)\n")

# Complete cases for W
cc_vars <- c("num_coal_mines_upstream", "sulfur_unified", "num_facilities",
             "POPULATION_SERVED_COUNT", "OWNER_TYPE_CODE", "PRIMARY_SOURCE_CODE",
             "state", "any_snsv", "v_hat", "log_delta_e", "B")
cc_mask  <- complete.cases(panel[, cc_vars])
panel_cc <- panel[cc_mask, ]
cat(sprintf("  Complete cases: %d / %d obs\n", nrow(panel_cc), nrow(panel)))

W <- model.matrix(
  ~ log(1 + num_coal_mines_upstream) + sulfur_unified +
    num_facilities + log(POPULATION_SERVED_COUNT + 1) +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
    factor(state) + any_snsv + v_hat,
  data = panel_cc
)
K       <- ncol(W)
W_names <- colnames(W)
cat(sprintf("  Design matrix W: %d obs x %d cols\n", nrow(W), K))

B_cc        <- panel_cc$B
log_delta_e <- panel_cc$log_delta_e

loglik_4 <- function(par) {
  delta_mu    <- par[1:K]
  delta_sigma <- par[(K + 1):(2 * K)]
  mu_it       <- as.numeric(W %*% delta_mu)
  sigma_it    <- exp(as.numeric(W %*% delta_sigma))
  eta_it      <- (log_delta_e - mu_it) / sigma_it
  p1          <- pnorm(eta_it, lower.tail = FALSE)   # Pr(B=1|x) = 1-Φ(η)
  p1          <- pmin(pmax(p1, 1e-12), 1 - 1e-12)
  -sum(B_cc * log(p1) + (1 - B_cc) * log(1 - p1))
}

s4_mu        <- rep(0, K)
s4_mu[1]     <- mean(log_delta_e, na.rm = TRUE) - qnorm(1 - mean(B_cc))
s4_sigma     <- rep(0, K)
start_4      <- c(s4_mu, s4_sigma)
fit_4 <- nlminb(start_4, loglik_4, control = list(iter.max = 3000, eval.max = 6000))
if (fit_4$convergence > 1)
  warning(sprintf("Eq. 4 nlminb: convergence issue (status %d): %s",
                  fit_4$convergence, fit_4$message))

delta_mu_hat    <- fit_4$par[1:K]
delta_sigma_hat <- fit_4$par[(K + 1):(2 * K)]
cat(sprintf("  Eq. 4 converged (status %d); log-lik = %.1f\n",
            fit_4$convergence, -fit_4$objective))

# Key sign diagnostic: δ_μ[mining] > 0 ⟹ higher compliance cost in mining areas
mu_mining_idx <- grep("num_coal_mines_upstream", W_names)[1]
if (!is.na(mu_mining_idx)) {
  cat(sprintf("  KEY: delta_mu[mining] = %.4f  (%s)\n",
              delta_mu_hat[mu_mining_idx],
              ifelse(delta_mu_hat[mu_mining_idx] > 0,
                     "POSITIVE — sign flip resolved",
                     "NEGATIVE — sign flip NOT resolved")))
}

# Helper closures (used in Eq. 5, counterfactuals, bootstrap)
mu_of    <- function(W_new) as.numeric(W_new %*% delta_mu_hat)
sigma_of <- function(W_new) exp(as.numeric(W_new %*% delta_sigma_hat))
F_of     <- function(theta, W_new) plnorm(theta, mu_of(W_new), sigma_of(W_new))
f_of     <- function(theta, W_new) dlnorm(theta, mu_of(W_new), sigma_of(W_new))

# Model-fit diagnostic
panel_cc$p_hat_struct <- 1 - F_of(exp(panel_cc$log_delta_e), W)
panel_cc$p_hat_eq3    <- predict(fit_3, newdata = panel_cc, type = "response")
fit_corr <- cor(panel_cc$p_hat_struct, panel_cc$p_hat_eq3, use = "complete.obs")
cat(sprintf("  Model-fit diagnostic: cor(1-F̂(Δê|x), p̂_eq3) = %.3f\n", fit_corr))


# ============================================================
# G. EQ. 5 — REGULATOR FOC NLS (OBSERVATION-LEVEL)
#    r_it = γ_it - θ*_it (1 + ψ_it) - ψ_it (1-F̂)/f̂
#    Minimize Σ_it r_it².  Overidentified by N - 2K → Hansen J-test.
# ============================================================
cat("-- Eq. 5: regulator FOC NLS (observation-level)\n")

W_reg  <- W
K_reg  <- ncol(W_reg)

theta_star <- exp(panel_cc$log_delta_e)
F_pts      <- F_of(theta_star, W)
f_pts      <- f_of(theta_star, W)

hazard   <- (1 - F_pts) / pmax(f_pts, 1e-14)
h_q99    <- quantile(hazard, 0.99, na.rm = TRUE)
if (max(hazard, na.rm = TRUE) > 5 * h_q99) {
  cat(sprintf("  Hazard tail: max=%.0f >> q99=%.0f — winsorizing at q99\n",
              max(hazard, na.rm = TRUE), h_q99))
}
hazard_w <- pmin(hazard, h_q99)

foc_resid_obs <- function(par) {
  beta_gamma <- par[1:K_reg]
  beta_psi   <- par[(K_reg + 1):(2 * K_reg)]
  gamma_it   <- exp(as.numeric(W_reg %*% beta_gamma))
  psi_it     <- exp(as.numeric(W_reg %*% beta_psi))
  resid      <- gamma_it - theta_star * (1 + psi_it) - psi_it * hazard_w
  sum(resid^2)
}

s5_gamma    <- rep(0, K_reg)
s5_gamma[1] <- log(mean(theta_star, na.rm = TRUE))
s5_psi      <- rep(0, K_reg)
s5_psi[1]   <- -4   # ψ ≈ 0.018 ≈ near-costless enforcement start
start_5 <- c(s5_gamma, s5_psi)
fit_5   <- nlminb(start_5, foc_resid_obs, control = list(iter.max = 3000, eval.max = 6000))
if (fit_5$convergence != 0)
  warning(sprintf("Eq. 5 nlminb did not converge: message = %s", fit_5$message))

beta_gamma_hat <- fit_5$par[1:K_reg]
beta_psi_hat   <- fit_5$par[(K_reg + 1):(2 * K_reg)]

panel_cc$gamma_hat <- exp(as.numeric(W_reg %*% beta_gamma_hat))
panel_cc$psi_hat   <- exp(as.numeric(W_reg %*% beta_psi_hat))

resid_vec     <- with(panel_cc,
                      gamma_hat - theta_star * (1 + psi_hat) - psi_hat * hazard_w)
j_stat_simple <- nrow(panel_cc) * mean(resid_vec^2) / var(resid_vec)
cat(sprintf("  Eq. 5 converged (status %d); SSR=%.2e; J(simple)=%.2f\n",
            fit_5$convergence, fit_5$objective, j_stat_simple))


# ============================================================
# G2. EQ. 5b ROBUSTNESS — BIN-LEVEL FOC NLS (K=4 IV-QUARTILES)
# ============================================================
cat("-- Eq. 5b: bin-level FOC NLS (robustness, K=4)\n")

post_cc <- panel_cc[panel_cc$post95 == 1 & panel_cc$z > 0, ]
brks    <- unique(quantile(post_cc$z, probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE))
panel_cc$z_bin <- cut(panel_cc$z, breaks = c(-Inf, brks[-1]),
                      labels = paste0("Q", seq_len(length(brks) - 1)),
                      include.lowest = TRUE)

bin_stats <- panel_cc |>
  group_by(z_bin) |>
  summarise(
    theta_k  = median(theta_star, na.rm = TRUE),
    F_k      = median(F_pts,      na.rm = TRUE),
    f_k      = median(f_pts,      na.rm = TRUE),
    hazard_k = median(hazard_w,   na.rm = TRUE),
    n        = n(),
    .groups  = "drop"
  )
K_bins <- nrow(bin_stats)

foc_bin_obj <- function(par) {
  beta_g <- par[1:2]; beta_p <- par[3:4]
  bin_idx <- seq_len(K_bins)
  gamma_k <- exp(beta_g[1] + beta_g[2] * bin_idx)
  psi_k   <- exp(beta_p[1] + beta_p[2] * bin_idx)
  resid_k <- gamma_k - bin_stats$theta_k * (1 + psi_k) - psi_k * bin_stats$hazard_k
  sum(resid_k^2)
}

fit_5b <- nlminb(c(0, 0, 0, 0), foc_bin_obj, control = list(iter.max = 1000))
cat(sprintf("  Eq. 5b converged (status %d); SSR=%.4f\n",
            fit_5b$convergence, fit_5b$objective))


# ============================================================
# H. EQ. 6 — SET-IDENTIFIED BOUNDS ON θ_i (PLUG-IN)
# ============================================================
panel_cc$theta_lower <- ifelse(panel_cc$B == 1, theta_star, NA_real_)
panel_cc$theta_upper <- ifelse(panel_cc$B == 0, theta_star, NA_real_)
cat(sprintf("-- Eq. 6: θ lower bound (B=1): median=%.1f, mean=%.1f days\n",
            median(panel_cc$theta_lower, na.rm = TRUE),
            mean(panel_cc$theta_lower,   na.rm = TRUE)))


# ============================================================
# I. EQ. 7 — EJ TESTS: READ OFF β̂_γ, β̂_ψ FROM EQ. 5
# ============================================================
cat("-- Eq. 7: EJ test — β̂_γ, β̂_ψ from Eq. 5\n")

ej_table <- data.frame(
  param      = W_names,
  beta_gamma = beta_gamma_hat,
  beta_psi   = beta_psi_hat,
  stringsAsFactors = FALSE
)

ej_mining <- ej_table[grep("upstream|sulfur", ej_table$param, ignore.case = TRUE), ]
cat("\nEJ headline coefficients:\n")
print(ej_mining)
cat("\nInterpretation: alpha_m = beta_gamma[mining], alpha_s = beta_gamma[sulfur]\n")
cat("  alpha_m < 0 => regulator perceives lower marginal harm in mining-exposed CWSs.\n")


# ============================================================
# J. BOOTSTRAP SEs (PWSID CLUSTER RESAMPLE, N_BOOT REPS)
#    Resamples PWSIDs and re-estimates Eqs. 1, 2a_formal, 2a_informal,
#    2b_formal, 2b_informal, 4, 5 in each rep.
# ============================================================
if (N_BOOT > 0) {
  cat(sprintf("-- Bootstrap SEs (%d reps; resampling %d PWSIDs)\n",
              N_BOOT, length(pwsids)))

  boot_mat_gamma <- matrix(NA_real_, nrow = N_BOOT, ncol = K_reg)
  boot_mat_psi   <- matrix(NA_real_, nrow = N_BOOT, ncol = K_reg)

  for (b in seq_len(N_BOOT)) {
    set.seed(b + 42L)

    # 1. Resample PWSIDs (with replacement)
    boot_ids <- sample(pwsids, replace = TRUE)
    bt_panel <- do.call(rbind, lapply(seq_along(boot_ids), function(j) {
      sub <- panel[panel$PWSID == boot_ids[j], ]
      sub$PWSID_bt <- paste0(boot_ids[j], "_", j)
      sub
    }))

    # 2. Eq. 1 on boot panel
    f1 <- tryCatch(
      feols(num_coal_mines_upstream ~ z + num_facilities |
              PWSID_bt + year + state,
            data = bt_panel, cluster = ~PWSID_bt, fixef.rm = "none"),
      error = function(e) NULL
    )
    if (is.null(f1)) next
    r1_bt <- residuals(f1)
    bt_panel$v_hat <- NA_real_
    if (length(r1_bt) == nrow(bt_panel)) {
      bt_panel$v_hat <- r1_bt
    } else {
      ki <- as.integer(names(r1_bt))
      bt_panel$v_hat[ki] <- r1_bt
    }

    # 3. Enforcement subsets for boot panel (original PWSID used to filter)
    formal_bt   <- bt_panel[bt_panel$PWSID %in% formal_pwsids, ]
    informal_bt <- bt_panel[bt_panel$PWSID %in% informal_pwsids, ]
    if (nrow(formal_bt) == 0 || nrow(informal_bt) == 0) next

    # 4. Eqs. 2a_formal and 2a_informal
    f2a_formal <- tryCatch(
      glm(formal_enf ~ B + log(1 + num_coal_mines_upstream) +
            num_facilities + POPULATION_SERVED_COUNT +
            factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + v_hat,
          family = binomial("probit"), data = formal_bt),
      error = function(e) NULL
    )
    f2a_informal <- tryCatch(
      glm(informal_enf ~ B + log(1 + num_coal_mines_upstream) +
            num_facilities + POPULATION_SERVED_COUNT +
            factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + v_hat,
          family = binomial("probit"), data = informal_bt),
      error = function(e) NULL
    )

    # 5. Eqs. 2b_formal and 2b_informal
    formal_bt_e1   <- bt_panel[bt_panel$formal_enf == 1 &
                                  !is.na(bt_panel$days_to_RTC_formal), ]
    informal_bt_e1 <- bt_panel[bt_panel$informal_enf == 1 & bt_panel$formal_enf == 0 &
                                  !is.na(bt_panel$days_to_RTC_informal), ]

    f2b_formal <- tryCatch(
      feols(log(days_to_RTC_formal + 1) ~ B + log(1 + num_coal_mines_upstream) +
              num_facilities + POPULATION_SERVED_COUNT |
              OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
            data = formal_bt_e1),
      error = function(e) NULL
    )
    f2b_informal <- tryCatch(
      feols(log(days_to_RTC_informal + 1) ~ B + log(1 + num_coal_mines_upstream) +
              num_facilities + POPULATION_SERVED_COUNT |
              OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
            data = informal_bt_e1),
      error = function(e) NULL
    )

    if (is.null(f2a_formal) || is.null(f2a_informal) ||
        is.null(f2b_formal) || is.null(f2b_informal)) next

    # 6. Recompute Δê for boot panel
    bt_pred_f <- bt_panel
    bt_pred_f$OWNER_TYPE_CODE[!bt_pred_f$OWNER_TYPE_CODE %in% owner_lvl_f] <- modal_owner_f
    bt_pred_f$PRIMARY_SOURCE_CODE[!bt_pred_f$PRIMARY_SOURCE_CODE %in% source_lvl_f] <- modal_src_f

    bt_pred_i <- bt_panel
    bt_pred_i$OWNER_TYPE_CODE[!bt_pred_i$OWNER_TYPE_CODE %in% owner_lvl_i] <- modal_owner_i
    bt_pred_i$PRIMARY_SOURCE_CODE[!bt_pred_i$PRIMARY_SOURCE_CODE %in% source_lvl_i] <- modal_src_i

    pf0_bt <- predict(f2a_formal, newdata = cbind(B=0L, bt_pred_f), type="response")
    pf1_bt <- predict(f2a_formal, newdata = cbind(B=1L, bt_pred_f), type="response")
    df0_bt <- exp(predict(f2b_formal, newdata = cbind(B=0L, bt_pred_f))) - 1
    df1_bt <- exp(predict(f2b_formal, newdata = cbind(B=1L, bt_pred_f))) - 1

    pi0_bt <- predict(f2a_informal, newdata = cbind(B=0L, bt_pred_i), type="response")
    pi1_bt <- predict(f2a_informal, newdata = cbind(B=1L, bt_pred_i), type="response")
    di0_bt <- exp(predict(f2b_informal, newdata = cbind(B=0L, bt_pred_i))) - 1
    di1_bt <- exp(predict(f2b_informal, newdata = cbind(B=1L, bt_pred_i))) - 1

    De_f_bt <- pmax(pf1_bt * pmax(df1_bt,0) - pf0_bt * pmax(df0_bt,0), 1e-6)
    De_i_bt <- pmax(pi1_bt * pmax(di1_bt,0) - pi0_bt * pmax(di0_bt,0), 1e-6)
    bt_panel$Delta_e     <- De_f_bt + kappa * De_i_bt
    bt_panel$log_delta_e <- log(bt_panel$Delta_e)

    # 7. Build W for boot complete cases
    bt_cc_mask <- complete.cases(bt_panel[, cc_vars])
    bt_cc <- bt_panel[bt_cc_mask, ]
    if (nrow(bt_cc) < 100) next

    W_bt <- tryCatch(
      model.matrix(
        ~ log(1 + num_coal_mines_upstream) + sulfur_unified +
          num_facilities + log(POPULATION_SERVED_COUNT + 1) +
          factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
          factor(state) + any_snsv + v_hat,
        data = bt_cc),
      error = function(e) NULL
    )
    if (is.null(W_bt)) next
    missing_cols <- setdiff(W_names, colnames(W_bt))
    for (mc in missing_cols) W_bt <- cbind(W_bt, setNames(data.frame(0), mc))
    W_bt <- W_bt[, W_names, drop = FALSE]

    # 8. Eq. 4 pseudo-likelihood
    B_bt   <- bt_cc$B
    lde_bt <- bt_cc$log_delta_e
    K_bt   <- ncol(W_bt)

    ll_bt <- function(par) {
      dmu <- par[1:K_bt]; dsi <- par[(K_bt+1):(2*K_bt)]
      mu  <- as.numeric(W_bt %*% dmu)
      sig <- exp(as.numeric(W_bt %*% dsi))
      eta <- (lde_bt - mu) / sig
      p1  <- pmin(pmax(pnorm(eta, lower.tail = FALSE), 1e-12), 1-1e-12)
      -sum(B_bt * log(p1) + (1 - B_bt) * log(1 - p1))
    }
    f4_bt <- tryCatch(
      nlminb(c(rep(0, K_bt), rep(log(0.5), K_bt)), ll_bt,
             control = list(iter.max = 2000, eval.max = 4000)),
      error = function(e) NULL
    )
    if (is.null(f4_bt) || f4_bt$convergence != 0) next

    dmu_bt <- f4_bt$par[1:K_bt]; dsi_bt <- f4_bt$par[(K_bt+1):(2*K_bt)]
    ts_bt  <- exp(lde_bt)
    F_bt   <- plnorm(ts_bt, as.numeric(W_bt %*% dmu_bt), exp(as.numeric(W_bt %*% dsi_bt)))
    f_bt   <- dlnorm(ts_bt, as.numeric(W_bt %*% dmu_bt), exp(as.numeric(W_bt %*% dsi_bt)))
    hz_bt  <- pmin((1 - F_bt) / pmax(f_bt, 1e-14),
                   quantile((1-F_bt)/pmax(f_bt,1e-14), 0.99, na.rm=TRUE))

    # 9. Eq. 5 NLS on boot
    foc_bt <- function(par) {
      bg <- par[1:K_bt]; bp <- par[(K_bt+1):(2*K_bt)]
      g  <- exp(as.numeric(W_bt %*% bg))
      ps <- exp(as.numeric(W_bt %*% bp))
      r  <- g - ts_bt * (1 + ps) - ps * hz_bt
      sum(r^2)
    }
    f5_bt <- tryCatch(
      nlminb(c(rep(0, K_bt), rep(0, K_bt)), foc_bt,
             control = list(iter.max = 2000, eval.max = 4000)),
      error = function(e) NULL
    )
    if (is.null(f5_bt) || f5_bt$convergence != 0) next

    boot_mat_gamma[b, ] <- f5_bt$par[1:K_bt]
    boot_mat_psi[b, ]   <- f5_bt$par[(K_bt+1):(2*K_bt)]

    if (b %% 50 == 0) cat(sprintf("  bootstrap: %d / %d done\n", b, N_BOOT))
  }

  good <- which(!is.na(boot_mat_gamma[, 1]))
  cat(sprintf("  Bootstrap completed: %d / %d successful reps\n", length(good), N_BOOT))

  ci_gamma <- apply(boot_mat_gamma[good, , drop = FALSE], 2,
                    quantile, probs = c(0.025, 0.975), na.rm = TRUE)
  ci_psi   <- apply(boot_mat_psi[good, , drop = FALSE], 2,
                    quantile, probs = c(0.025, 0.975), na.rm = TRUE)
  colnames(ci_gamma) <- colnames(ci_psi) <- W_names

  ej_table$ci_lo_gamma <- ci_gamma[1, ]
  ej_table$ci_hi_gamma <- ci_gamma[2, ]
  ej_table$ci_lo_psi   <- ci_psi[1, ]
  ej_table$ci_hi_psi   <- ci_psi[2, ]
} else {
  cat("-- Bootstrap skipped (N_BOOT = 0)\n")
  ej_table$ci_lo_gamma <- NA_real_; ej_table$ci_hi_gamma <- NA_real_
  ej_table$ci_lo_psi   <- NA_real_; ej_table$ci_hi_psi   <- NA_real_
  boot_mat_gamma <- NULL; boot_mat_psi <- NULL
}


# ============================================================
# K. COUNTERFACTUALS
# ============================================================
cat("-- Counterfactuals\n")

theta_obs  <- theta_star
gamma_obs  <- panel_cc$gamma_hat
psi_obs    <- panel_cc$psi_hat
mu_obs     <- as.numeric(W %*% delta_mu_hat)
sigma_obs  <- exp(as.numeric(W %*% delta_sigma_hat))
p_obs      <- 1 - plnorm(theta_obs, mu_obs, sigma_obs)
N_cc       <- nrow(panel_cc)

# ── CF1: one-size-fits-all enforcement schedule ──────────────────────────────
pop_cost_cf1 <- function(theta_bar) {
  F_bar    <- plnorm(theta_bar, mu_obs, sigma_obs)
  cost_env <- gamma_obs * (1 - F_bar)
  cost_com <- theta_bar * F_bar
  cost_enf <- psi_obs * theta_bar
  mean(cost_env + cost_com + cost_enf)
}
opt_cf1   <- optimize(pop_cost_cf1, c(1e-3, 5e3))
theta_cf1 <- opt_cf1$minimum
p_cf1     <- 1 - plnorm(theta_cf1, mu_obs, sigma_obs)
cat(sprintf("  CF1 uniform θ* = %.1f days; Δ viol incidence = %+.3f pp\n",
            theta_cf1, 100 * (mean(p_cf1) - mean(p_obs))))

# ── CF2: equalized regulator preferences (EJ counterfactual) ─────────────────
W_eq <- W_reg
mining_col <- grep("upstream", W_names, ignore.case = TRUE)
if (length(mining_col) > 0) W_eq[, mining_col] <- 0

gamma_eq <- exp(as.numeric(W_eq %*% beta_gamma_hat))
psi_eq   <- exp(as.numeric(W_eq %*% beta_psi_hat))
mu_eq    <- as.numeric(W_eq %*% delta_mu_hat)
sigma_eq <- exp(as.numeric(W_eq %*% delta_sigma_hat))

theta_cf2 <- mapply(solve_theta_star,
                    gamma_i = gamma_eq, psi_i = psi_eq,
                    mu_i = mu_eq, sigma_i = sigma_eq)
p_cf2 <- 1 - plnorm(theta_cf2, mu_eq, sigma_eq)
cat(sprintf("  CF2 equalized γ/ψ: Δ viol incidence = %+.3f pp\n",
            100 * (mean(p_cf2, na.rm = TRUE) - mean(p_obs))))

# ── CF3: first-best (ψ = 0) ──────────────────────────────────────────────────
theta_cf3 <- gamma_obs
p_cf3     <- 1 - plnorm(theta_cf3, mu_obs, sigma_obs)
cat(sprintf("  CF3 first-best (ψ=0): Δ viol incidence = %+.3f pp\n",
            100 * (mean(p_cf3) - mean(p_obs))))

# ── CF4: green regulator upper bound ─────────────────────────────────────────
gamma_max <- max(gamma_obs)
psi_min   <- min(psi_obs)
theta_cf4 <- mapply(solve_theta_star,
                    gamma_i = gamma_max, psi_i = psi_min,
                    mu_i = mu_obs, sigma_i = sigma_obs)
p_cf4 <- 1 - plnorm(theta_cf4, mu_obs, sigma_obs)
cat(sprintf("  CF4 green regulator: Δ viol incidence = %+.3f pp\n",
            100 * (mean(p_cf4, na.rm = TRUE) - mean(p_obs))))

# ── CF5: no-mining counterfactual ────────────────────────────────────────────
W_nm <- W_reg
if (length(mining_col) > 0) W_nm[, mining_col] <- 0
gamma_nm <- exp(as.numeric(W_nm %*% beta_gamma_hat))
psi_nm   <- exp(as.numeric(W_nm %*% beta_psi_hat))
mu_nm    <- as.numeric(W_nm %*% delta_mu_hat)
sigma_nm <- exp(as.numeric(W_nm %*% delta_sigma_hat))

theta_cf5    <- mapply(solve_theta_star,
                       gamma_i = gamma_nm, psi_i = psi_nm,
                       mu_i = mu_nm, sigma_i = sigma_nm)
p_cf5_fixed  <- 1 - plnorm(theta_obs, mu_nm, sigma_nm)
p_cf5_equil  <- 1 - plnorm(theta_cf5, mu_nm, sigma_nm)

delta_cf5_direct   <- mean(p_cf5_fixed, na.rm = TRUE) - mean(p_obs)
delta_cf5_retailor <- mean(p_cf5_equil, na.rm = TRUE) - mean(p_cf5_fixed, na.rm = TRUE)
delta_cf5_total    <- delta_cf5_direct + delta_cf5_retailor

cat(sprintf("  CF5 no-mining: Δ total=%+.3f pp (direct=%+.3f; retailor=%+.3f)\n",
            100 * delta_cf5_total, 100 * delta_cf5_direct, 100 * delta_cf5_retailor))

# ── CF Validation: out-of-sample structural-stability test ───────────────────
top_iv_mask <- !is.na(panel_cc$z_bin) & panel_cc$z_bin == "Q4"
if (sum(top_iv_mask) > 20) {
  W_lo   <- W[!top_iv_mask, , drop = FALSE]
  B_lo   <- B_cc[!top_iv_mask]
  lde_lo <- log_delta_e[!top_iv_mask]
  ll_lo  <- function(par) {
    dmu <- par[1:K]; dsi <- par[(K+1):(2*K)]
    eta <- (lde_lo - as.numeric(W_lo %*% dmu)) / exp(as.numeric(W_lo %*% dsi))
    p1  <- pmin(pmax(pnorm(eta, lower.tail = FALSE), 1e-12), 1-1e-12)
    -sum(B_lo * log(p1) + (1 - B_lo) * log(1 - p1))
  }
  f4_lo <- tryCatch(
    nlminb(start_4, ll_lo, control = list(iter.max = 2000)),
    error = function(e) NULL
  )
  if (!is.null(f4_lo)) {
    dmu_lo <- f4_lo$par[1:K]; dsi_lo <- f4_lo$par[(K+1):(2*K)]
    W_hi   <- W[top_iv_mask, , drop = FALSE]
    eta_hi <- (log_delta_e[top_iv_mask] - as.numeric(W_hi %*% dmu_lo)) /
              exp(as.numeric(W_hi %*% dsi_lo))
    p_pred_hi <- pnorm(eta_hi, lower.tail = FALSE)
    p_obs_hi  <- B_cc[top_iv_mask]
    corr_oos  <- cor(p_pred_hi, p_obs_hi, use = "complete.obs")
    cat(sprintf("  CF Validation (OOS Q4 n=%d): cor(p_pred, B_obs) = %.3f\n",
                sum(top_iv_mask), corr_oos))
  }
}


# ============================================================
# L. EXPORT FIGURES
# ============================================================
dir.create("output/struct", showWarnings = FALSE, recursive = TRUE)
dir.create("output/reg",    showWarnings = FALSE, recursive = TRUE)
dir.create("output/fig",    showWarnings = FALSE, recursive = TRUE)

cf_df <- data.frame(
  scenario = c("Observed", "CF1: Uniform", "CF2: Equal γ/ψ",
               "CF3: First-best", "CF4: Green", "CF5: No mining"),
  mean_p   = c(mean(p_obs),
               mean(p_cf1),
               mean(p_cf2,        na.rm = TRUE),
               mean(p_cf3),
               mean(p_cf4,        na.rm = TRUE),
               mean(p_cf5_equil,  na.rm = TRUE))
)
cf_df$scenario <- factor(cf_df$scenario, levels = cf_df$scenario)

g_cf <- ggplot(cf_df, aes(x = scenario, y = mean_p * 100)) +
  geom_col(fill = "steelblue", width = 0.6) +
  geom_hline(yintercept = mean(p_obs) * 100, linetype = "dashed", colour = "grey40") +
  labs(x = NULL, y = "Mean Pr(B = 1) [%]",
       caption = "Downstream CWSs, 1985-2005. Dashed line = observed.") +
  theme_minimal(base_size = 12) +
  theme(panel.grid.major.x = element_blank(),
        axis.text.x = element_text(angle = 20, hjust = 1))
ggsave("output/fig/binary_counterfactuals.png",
       plot = g_cf, width = 7, height = 4, dpi = 200)
cat("Wrote: output/fig/binary_counterfactuals.png\n")


# ============================================================
# M. EXPORT EJ TABLE (structural_eq7.tex)
# ============================================================
ej_display <- ej_table

label_map <- c(
  "(Intercept)"                              = "Intercept",
  "log(1 + num_coal_mines_upstream)"         = "$\\log(1+\\text{mines})$",
  "sulfur_unified"                           = "Sulfur \\%",
  "num_facilities"                           = "N facilities",
  "log(POPULATION_SERVED_COUNT + 1)"         = "$\\log$ population",
  "any_snsv"                                 = "Sanitary survey",
  "v_hat"                                    = "CF residual $\\hat{v}$"
)
ej_display$label <- ifelse(ej_display$param %in% names(label_map),
                           label_map[ej_display$param],
                           gsub("factor\\((.+)\\)(.*)", "\\1: \\2", ej_display$param))

fmt_coef <- function(x) sprintf("%.3f", x)
fmt_ci   <- function(lo, hi) ifelse(is.na(lo), "", sprintf("[%.3f, %.3f]", lo, hi))

tex_rows <- apply(ej_display, 1, function(r) {
  paste0(r["label"], " & ",
         fmt_coef(as.numeric(r["beta_gamma"])), " & ",
         fmt_ci(as.numeric(r["ci_lo_gamma"]), as.numeric(r["ci_hi_gamma"])), " & ",
         fmt_coef(as.numeric(r["beta_psi"])),   " & ",
         fmt_ci(as.numeric(r["ci_lo_psi"]),   as.numeric(r["ci_hi_psi"])), " \\\\")
})

tex_lines <- c(
  "\\begin{tabular}{lcccc}",
  "\\toprule",
  paste0(" & \\multicolumn{2}{c}{$\\hat{\\beta}_\\gamma$",
         " (perceived harm)} & \\multicolumn{2}{c}{$\\hat{\\beta}_\\psi$",
         " (enforcement cost)} \\\\"),
  "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}",
  "Covariate & Estimate & 95\\% CI & Estimate & 95\\% CI \\\\",
  "\\midrule",
  tex_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\par \\raggedright",
  paste0("\\footnotesize Notes: Eq.\\ 5 observation-level NLS on ",
         N_cc, " PWSID-years (downstream, 1985--2005). ",
         "Log-normal $F(\\theta|x)$ from Eq.\\ 4 pseudo-likelihood (formal-only $\\Delta\\hat{e}$). ",
         "95\\% CIs from PWSID-clustered percentile bootstrap (", N_BOOT, " reps). ",
         "$\\alpha_m < 0$ indicates regulator perceives lower marginal harm in ",
         "mining-exposed CWSs."),
  "\\par"
)

out_tex <- "output/reg/structural_eq7.tex"
writeLines(tex_lines, out_tex)
wrap_for_beamer(out_tex)
cat(sprintf("Wrote: %s\n", out_tex))


# ============================================================
# N. SAVE RDS
# ============================================================
saveRDS(
  list(
    panel_cc        = panel_cc,
    fit_1           = fit_1,
    fit_2a_formal   = fit_2a_formal,
    fit_2a_informal = fit_2a_informal,
    fit_2b_formal   = fit_2b_formal,
    fit_2b_informal = fit_2b_informal,
    fit_3           = fit_3,
    fit_4           = fit_4,
    fit_5           = fit_5,
    fit_5b          = fit_5b,
    delta_mu_hat    = delta_mu_hat,
    delta_sigma_hat = delta_sigma_hat,
    beta_gamma_hat  = beta_gamma_hat,
    beta_psi_hat    = beta_psi_hat,
    ej_table        = ej_table,
    boot_gamma      = boot_mat_gamma,
    boot_psi        = boot_mat_psi,
    W               = W,
    W_names         = W_names,
    kappa           = kappa,
    cf = list(cf1 = list(theta = theta_cf1, p = p_cf1),
              cf2 = list(theta = theta_cf2, p = p_cf2),
              cf3 = list(theta = theta_cf3, p = p_cf3),
              cf4 = list(theta = theta_cf4, p = p_cf4),
              cf5 = list(theta_nm = theta_cf5, p_fixed = p_cf5_fixed,
                         p_equil = p_cf5_equil))
  ),
  "output/struct/primitives_binary.rds"
)
cat("Wrote: output/struct/primitives_binary.rds\n")

cat("\n==========================================================\n")
cat("DONE.  Eq. 1-7 + CFs complete.\n")
cat("  output/struct/primitives_binary.rds\n")
cat("  output/reg/structural_eq7.tex\n")
cat("  output/fig/binary_counterfactuals.png\n")
cat("==========================================================\n")
