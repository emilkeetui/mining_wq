# Adapting Kang and Silveira (2021) to the Coal Mining × Drinking Water Quality Setting — Binary-Choice Variant

A static structural model of CWS compliance and SDWA enforcement, identified with an IV instead of a policy-regime shift, in which the firm's action is a binary {comply, MR} decision rather than a continuous negligence level.

---

## 1. Motivation and Headline Verdict

The continuous-action K&S adaptation drafted earlier in this log failed two of its three feasibility checks (§15 below). The MR-day count `K_it` is essentially Bernoulli — 89% zeros, and the 10.98% nonzero observations are *all* at K = 365 days — so the Poisson-mixture identification of the negligence distribution `G(a|x)` (K&S Lemma 1) degenerates and the LPV walk has no interior support to traverse. The penalty schedule has clear deterrence content on the linear margin (Check 2 passed) but no estimable curvature in `K`, so the firm FOC `θ·b'(a) = e'(a|x)` collapses to a single comparison.

The data is telling us, in effect, that within a year a CWS is either fully out of MR compliance or fully in it. That is exactly the structure a discrete-effort Mookherjee–Png / Becker model handles. The binary-choice variant:

- Replaces continuous `a ∈ [0, ā]` with `B_it ∈ {0, 1}`.
- Replaces `G(a|x)` with `p(x) = Pr(B = 1 | x)`, directly observable.
- Replaces the LPV walk with a probit + cross-`x`-bin moment system.
- Retains the regulator-preference primitives `γ(x), ψ(x)` — the EJ object that motivated the structural project in the first place.
- Retains the no-mining counterfactual CF5 that reduced-form 2SLS cannot produce.

What is lost: the curve `b'(a)` (one scale parameter `c` survives, normalized to 1), the type distribution as a nonparametric object (it is now identified parametrically at one point per `x`-bin), and the "negligence schedule" rhetorical pitch.

The remaining identification risk is the same one Check 3 surfaced for the continuous model: at the top of the IV support, `p(x)` may not be monotone in `x`, which is what the binary version needs in place of LPV stochastic-ordering. `binary_feasibility.r` (§9) checks this directly.

This is the right version to write the paper around.

---

## 2. Theoretical Underpinnings

### 2.1 The Mookherjee–Png / Becker family with discrete effort

Firms choose `B_i ∈ {0, 1}`, where `B = 1` denotes failing to comply with monitoring/reporting requirements ("negligence") and `B = 0` denotes compliance. The model sits in the Becker (1968) tradition with the Mookherjee–Png (1994) twist that the regulator commits ex ante to a penalty schedule that depends on the observed action. Compared with K&S 2021, the action is discretized; everything else (private type, regulator preferences `γ, ψ`, costly enforcement) carries over.

### 2.2 Model setup

There are many CWSs indexed by `i`, one regulator.

**Firm primitives.**
- Type `θ_i ~ F(·|x_i)`, with `x_i` a vector of CWS attributes (mining exposure, sulfur, size, primacy state, …). `θ` is the firm's idiosyncratic cost of compliance.
- Action `B_i ∈ {0, 1}`. Observed: number of MR-violation-days in year `t` is `365·B_it` (Check 1 of §15 confirms `B` is the right granularity).
- Compliance saving: `θ·c`, where `c = b(0) − b(1) > 0` is the gross resource saving from non-compliance. Normalize `c = 1` (one scale normalization, analogous to K&S `b'(a₀) = 1`).

**Regulator primitives.**
- Knows `F(θ|x)`, observes `B_i` (and `x_i`) but not `θ_i`.
- Commits to a two-point penalty schedule `(e(0|x), e(1|x))`. The relevant object is the differential `Δe(x) ≡ e(1|x) − e(0|x)`, the expected enforcement burden of choosing `B = 1` rather than `B = 0`. Empirically this is the product of `Pr(any enforcement | B, x)` and `E[days_to_RTC | enforcement, B, x]`.
- Perceived environmental harm: `h(B|x) = γ(x)·B` (linear).
- Marginal cost per unit of enforcement: `ψ(x)`.
- Regulator's objective (to minimize):

```
E[ γ(x)·B(θ) + θ·c·{1 − B(θ)} + ψ(x)·e(B(θ)|x) ]
```

### 2.3 First-order conditions

**Firm threshold.** Given `(e(0|x), e(1|x))`, the firm picks `B = 1` iff `θ·c ≥ Δe(x)`. With `c = 1`, the equilibrium cutoff is

```
θ*(x) = Δe(x).
```

Pr(B = 1 | x) = 1 − F(θ*(x) | x). This is the discrete analogue of K&S's firm FOC.

**Regulator FOC.** The regulator chooses `Δe(x)` (equivalently `θ*`) to minimize the expected social cost. After taking the derivative and substituting the threshold:

```
γ(x) = θ*(x) + ψ(x) · [ Δe(x) + (1 − F(θ*|x)) / f(θ*|x) ]
     = θ*(x) · (1 + ψ(x)) + ψ(x) · (1 − F(θ*|x)) / f(θ*|x).
```

The hazard term `(1 − F)/f` is the asymmetric-information rent the regulator pays at the cutoff. This equation pins down `(γ(x), ψ(x))` once `θ*(x)`, `F(θ*|x)`, and `f(θ*|x)` are known.

### 2.4 The IV-adapted identification

There is no regime shift in `e(·)` in the SDWA setting; the variation is in `x` (mining exposure), driven exogenously by `z = post95 × sulfur_unified`. Identification proceeds in four steps:

1. **Threshold `θ*(x)`.** Estimate `Δê(x)` from a two-equation enforcement sub-model on the 268-PWSID enforcement subsample. With `c = 1`, `θ̂*(x) = Δê(x)`.
2. **Compliance probability `p̂(x)`.** Probit (or logit) of `B_it` on `x_it` and the control-function residual `v̂_it` from the first stage.
3. **Type distribution `F(·|x)`.** Parametrize `F(·|x)` flexibly (e.g., log-normal with mean and scale linear in `x`). Use the moment `F(θ̂*(x_k) | x_k) = 1 − p̂(x_k)` at each `x`-bin `k` to estimate the parameters by GMM. With ≥ 2 `x`-bins this is identified; with more bins it is overidentified.
4. **Regulator preferences `γ(x), ψ(x)`.** Plug `θ̂*(x)`, `F̂(θ̂*|x)`, `f̂(θ̂*|x)` into the regulator FOC at each `x`-bin. Each bin gives one equation in `(γ(x), ψ(x))`. Across bins, parametrize `log γ(x)` and `log ψ(x)` as linear in `x` and estimate by nonlinear least squares (or GMM with the FOC residuals as moments).

The exclusion restriction (`z` enters only through `x`) is the same one the reduced-form 2SLS already imposes.

---

## 3. Supporting Literature

### 3.1 Direct ancestors

- **Becker (1968) JPE** — Foundational deterrence model.
- **Mookherjee and Png (1994) JPE** — Marginal deterrence with asymmetric information; the discrete-effort branch is the closest precedent for the binary variant.
- **Kang and Silveira (2021) JPE** — Continuous-action recovery of `(F, b', γ, ψ)` from a 2006 regime shift; the model we depart from.

### 3.2 Discrete-choice / threshold-crossing identification

- **Manski (1985, 1988)** — Maximum-score / threshold-crossing identification with a single index.
- **Matzkin (1992) Econometrica** — Nonparametric identification of threshold-crossing models.
- **Aradillas-Lopez (2010)** — Semiparametric estimation of binary-choice games (the discrete-effort literature most closely resembling this setup).
- **Bajari, Hong, Krainer, Nekipelov (2010) JoE** — Estimation of discrete games with private information; same firm-side structure used here.

### 3.3 Structural environmental enforcement

- **Duflo, Greenstone, Pande, Ryan (2018) Econometrica** — Field experiment on regulator targeting; closest precedent for `γ(x)`-type objects.
- **Blundell, Gowrisankaran, Langer (2020) AER** — Clean Air Act dynamic enforcement.
- **Ryan (2012) Econometrica** — Cement industry; static theory + dynamic estimation.
- **Helland (1998)** — State EPA enforcement preferences and substitution; conceptual antecedent for `γ(x)`.

### 3.4 Water quality and CWA/SDWA reduced-form

- **Keiser and Shapiro (2019) QJE** — CWA effects on water quality; reduced-form benchmark.
- **Earnhart (2004a, b)** — Wastewater treatment plant compliance panels.
- **Gray and Shimshack (2011)** — Survey of monitoring and enforcement.

### 3.5 Acid Rain Program / coal-quality IV

- Carlson, Burtraw, Cropper, Palmer (2000); Chan, Chupp, Cropper, Muller (2018). Motivation for first-stage variation; not used in the structural model directly.

---

## 4. Data

### 4.1 Unit of observation

PWSID × year, 1985–2005, downstream-only sample:
- Filter: `minehuc_downstream_of_mine == 1 & minehuc_mine == 0`
- N = 6,232 PWSID × year observations
- 340 unique CWSs
- `WV3303401` dropped (known outlier)

### 4.2 Key variables

**Outcome / firm action.**
- `B_it = 1` if the CWS had any MR-violation-day across mining-related contaminants (nitrates, arsenic, inorganic chemicals, radionuclides) in year `t`. Otherwise `B_it = 0`. Empirical share: 11.0% of observations have `B = 1`; nonzero outcomes are concentrated at 365 days, justifying the binary recasting.

**Endogenous variable.**
- `m_it = num_coal_mines_upstream_mean` (alternative: `production_short_tons_coal_upstream_mean`).

**Instrument.**
- `z_it = post95 × sulfur_unified_mean`. First-stage F = 13.6 (from Priority 0 checks).

**Enforcement (regulator action).**
- `any_enforcement_it = 1` if any formal or informal SDWA enforcement action recorded that year for CWS `i`. Constructed from the 268 PWSIDs with enforcement records.
- `days_to_RTC_it` = days from violation onset to return-to-compliance. Median 183, mean 332.

**Covariates `x_it`.**
- `num_facilities`, `POPULATION_SERVED_COUNT`, `OWNER_TYPE_CODE`, `PRIMARY_SOURCE_CODE`, `sulfur_unified`, plus state and year fixed effects.

### 4.3 Data quality caveats

- **MCL violations remain too sparse for separate structural treatment.** Only 4.4% of downstream CWSs ever report an MCL violation in mining-related contaminants. Model is restricted to MR margin.
- **Penalty amounts are not in dollars.** As in the continuous version, the regulator's "expected penalty" is reconstructed from `Pr(enforcement) × E[days-to-RTC]`.
- **Sanitary surveys are sparse.** Used as time-invariant covariate, not state.

---

## 5. Estimating Equations

Notation: `i` = CWS, `t` = year. `x_it` = covariates. `z_it` = `post95 × sulfur_unified`. `B_it` = MR-violation indicator. `E_it` = enforcement indicator.

### Equation 1 — First stage / control function

```
m_it = π·z_it + x_it'·ρ + η_i + τ_t + ν_it
```

Save `v̂_it`. The exclusion restriction is the standard 2SLS one.

### Equation 2 — Enforcement burden by action and `x`

Estimate two equations on the 268-PWSID enforcement subsample:

```
(2a)  Pr(E_it = 1 | B_it, x_it, v̂_it) = Φ(φ₀ + φ_B·B_it + x_it'·φ_x + φ_v·v̂_it)
(2b)  log(days_to_RTC_it + 1) | E_it = 1  = ξ₀ + ξ_B·B_it + x_it'·ξ_x + u_it
```

Construct the two-point schedule:

```
ê(B | x) = Pr̂(E = 1 | B, x) · Ê[days_to_RTC | E = 1, B, x],   B ∈ {0, 1}
Δê(x)    = ê(1 | x) − ê(0 | x)
```

With `c = 1`, the firm threshold is `θ̂*(x) = Δê(x)`.

### Equation 3 — Compliance probability (firm side)

```
p̂(x_it) = Pr(B_it = 1 | x_it, v̂_it) = Φ(α₀ + α_m·log(1 + m_it) + α_s·sulfur_it + x_it'·α_x + α_v·v̂_it)
```

This is the discrete analogue of `G(a|x)`. Equivalent to the reduced-form probit on whether the CWS ever had an MR violation in the year, with the control-function correction for endogeneity of `m`.

### Equation 4 — Type distribution `F(·|x)`

Parametrize log-normal:

```
log θ | x ~ N(μ(x), σ²(x)),     μ(x) = w_it'·δ_μ,  log σ(x) = w_it'·δ_σ.
```

Identify by matching the cross-`x`-bin moments

```
F( θ̂*(x_k) | x_k ) = 1 − p̂(x_k),   k = 1, …, K bins.
```

`K` ≥ 2 identifies a one-parameter F per bin; cross-bin restrictions (`δ_μ`, `δ_σ` linear in `x`) deliver overidentification. Estimate by GMM with bootstrap SEs (resample PWSIDs).

### Equation 5 — Regulator FOC system

At each `x`-bin `k`, the FOC

```
γ(x_k) = θ̂*(x_k) · (1 + ψ(x_k)) + ψ(x_k) · ( 1 − F̂(θ̂*(x_k)|x_k) ) / f̂(θ̂*(x_k)|x_k)
```

with `log γ(x) = β_γ' x_k + ν_k`, `log ψ(x) = β_ψ' x_k + ν_k'` estimated by nonlinear least squares on the bin-level residuals. Overidentified for `K ≥ 3`.

### Equation 6 — Recovered firm-level compliance cost (plug-in)

```
θ̂_it = Δê(x_it)   if B_it = 1   (lower bound on θ)
θ̂_it ≤ Δê(x_it)   if B_it = 0   (upper bound)
```

In the discrete-action setting `θ_i` is only set-identified at the unit level. Distributional statements use `F̂(·|x)` directly.

### Equation 7 — Regulator EJ tests

```
(7a)  log γ̂(x_it) = α₀ + α_m·log(1 + mining_it) + α_s·sulfur_it + w_it'·α_w + ξ_it
(7b)  log ψ̂(x_it) = μ₀ + μ_m·log(1 + mining_it) + μ_s·sulfur_it + w_it'·μ_w + ζ_it
```

`α_m < 0` ⟹ regulator perceives lower marginal harm per MR violation in mining-exposed CWSs. This is the headline EJ test.

---

## 6. Data → Estimator → Output

| Step | Input data | Estimator | Output |
|---|---|---|---|
| Eq. 1 | Full panel | OLS (`feols`) | `v̂_it` |
| Eq. 2a | 268-PWSID enforcement panel | Probit | Pr̂(E=1 \| B, x) |
| Eq. 2b | Same, E=1 subset | OLS (`feols`) | Ê[days_to_RTC \| B, x] |
| Eq. 2 | Outputs of 2a, 2b | Construction | `ê(B \| x)`, `Δê(x)` |
| Eq. 3 | Full panel | Probit with CF correction | `p̂(x)` |
| Eq. 4 | `Δê(x_k)`, `p̂(x_k)` across bins | GMM (`gmm` or `nlminb`) | `δ_μ`, `δ_σ` ⟹ `F̂(·\|x)` |
| Eq. 5 | Bin-level `(θ*, F, f)` | NLS | `γ̂(x)`, `ψ̂(x)` |
| Eq. 6 | Plug-in | — | Set bounds on `θ_i` |
| Eq. 7a/b | `γ̂(x_it)`, `ψ̂(x_it)`, `x_it` | OLS w/ bootstrap SE | `α_m`, `μ_m` |

### 6.1 IV-bin construction

`x`-bins are quartiles of the predicted endogenous variable from Eq. 1, computed in the post-95 subsample (where the IV has bite). Quartile cut points are fixed at the post-95 distribution and applied to the full panel for prediction.

---

## 7. Pseudocode

```r
# ============================================================
# Script: structural_ks_binary.r
# Purpose: K&S-adapted static structural model with binary firm action
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: output/struct/primitives_binary.rds
#          output/reg/structural_eq7.tex
#          output/fig/binary_counterfactuals.png
# ============================================================

library(arrow); library(fixest); library(dplyr); library(tidyr); library(gmm)

# --- Load and construct B_it ---
panel <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet") |>
  filter(minehuc_downstream_of_mine == 1, minehuc_mine == 0,
         year >= 1985, year <= 2005, PWSID != "WV3303401")
mining <- c("nitrates","arsenic","inorganic_chemicals","radionuclides")
mr_days <- paste0(mining,"_MR_share_days")
panel$B <- as.integer(rowSums(panel[, mr_days], na.rm = TRUE) > 0)

# --- Eq. 1: first stage ---
fit_1 <- feols(num_coal_mines_upstream_mean ~ I(post95*sulfur_unified_mean) +
                 num_facilities | PWSID + year + STATE_CODE,
               data = panel, cluster = ~PWSID)
panel$v_hat <- residuals(fit_1)

# --- Eq. 2a, 2b: enforcement schedule ---
# (load enforcement file, merge, build any_enforcement and days_to_RTC, as in priority0)

fit_2a <- glm(any_enforcement ~ B + num_facilities + POPULATION_SERVED_COUNT +
                factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + v_hat,
              family = binomial("probit"), data = enf_panel)

fit_2b <- feols(log(days_to_RTC + 1) ~ B + num_facilities + POPULATION_SERVED_COUNT |
                  OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
                data = filter(enf_panel, any_enforcement == 1))

e_hat <- function(B_val, x_row) {
  p <- predict(fit_2a, newdata = cbind(B = B_val, x_row), type = "response")
  d <- exp(predict(fit_2b, newdata = cbind(B = B_val, x_row))) - 1
  p * d
}
Delta_e_hat <- function(x_row) e_hat(1, x_row) - e_hat(0, x_row)

# --- Eq. 3: compliance probability ---
fit_3 <- glm(B ~ log(1 + num_coal_mines_upstream_mean) + sulfur_unified_mean +
               num_facilities + POPULATION_SERVED_COUNT +
               factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + v_hat,
             family = binomial("probit"), data = panel)

# --- Eq. 4: F(θ|x) via GMM moments ---
# Build x-bins
panel$xb <- ntile(predict(fit_1, type = "response"), 4)

bin_table <- panel |>
  group_by(xb) |>
  summarise(
    theta_star = Delta_e_hat(across(everything(), median)),
    p_hat      = mean(predict(fit_3, type = "response"))
  )

# Log-normal F(·|x): identify (mu_k, sigma_k) from (theta_star_k, p_hat_k)
#   F(theta_star_k | mu_k, sigma_k) = 1 - p_hat_k
# With cross-bin parametrization mu(x) = w'delta_mu, log sigma(x) = w'delta_sigma:
gmm_moments <- function(par, data) {
  delta_mu    <- par[1:p_mu]
  delta_sigma <- par[(p_mu + 1):(p_mu + p_sigma)]
  mu_k        <- as.matrix(data$w) %*% delta_mu
  sigma_k     <- exp(as.matrix(data$w) %*% delta_sigma)
  resid       <- plnorm(data$theta_star, mu_k, sigma_k) - (1 - data$p_hat)
  cbind(resid, resid * data$w)
}
fit_4 <- gmm::gmm(gmm_moments, x = bin_table, t0 = rep(0, p_mu + p_sigma))

# --- Eq. 5: γ(x), ψ(x) via NLS on FOC residuals ---
foc_resid <- function(par, bin_table, F_fit) {
  beta_gamma <- par[1:p_g]; beta_psi <- par[(p_g+1):(p_g+p_p)]
  gamma_k <- exp(as.matrix(bin_table$w) %*% beta_gamma)
  psi_k   <- exp(as.matrix(bin_table$w) %*% beta_psi)
  theta   <- bin_table$theta_star
  F_pts   <- plnorm(theta, mu_k(F_fit, bin_table$w), sigma_k(F_fit, bin_table$w))
  f_pts   <- dlnorm(theta, mu_k(F_fit, bin_table$w), sigma_k(F_fit, bin_table$w))
  gamma_k - theta * (1 + psi_k) - psi_k * (1 - F_pts) / f_pts
}
fit_5 <- nls.lm(par = rep(0, p_g + p_p), fn = foc_resid,
                bin_table = bin_table, F_fit = fit_4)

# --- Eq. 7: EJ tests on recovered γ, ψ ---
panel$gamma_hat <- gamma_of(panel$x, fit_5)
panel$psi_hat   <- psi_of(panel$x, fit_5)

fit_7a <- feols(log(gamma_hat) ~ log(1 + num_coal_mines_upstream_mean) +
                  sulfur_unified_mean + num_facilities + POPULATION_SERVED_COUNT,
                data = panel, cluster = ~PWSID)
fit_7b <- feols(log(psi_hat) ~ log(1 + num_coal_mines_upstream_mean) +
                  sulfur_unified_mean + num_facilities + POPULATION_SERVED_COUNT,
                data = panel, cluster = ~PWSID)

# Bootstrap SE: resample PWSIDs, redo Eqs. 1-5, store gamma/psi, repeat 500x

saveRDS(list(fit_1, fit_2a, fit_2b, fit_3, fit_4, fit_5, fit_7a, fit_7b,
             panel),
        "output/struct/primitives_binary.rds")
```

---

## 8. Counterfactuals

Each CF holds `(F̂(·|x), γ̂(x), ψ̂(x))` fixed and re-solves the regulator's binary problem.

### CF1 — One-size-fits-all SDWA enforcement

**Question.** What if EPA imposed a single `(ē(0), ē(1))` applied to all CWSs?

**Computation.**
1. Pick `(ē(0), ē(1))` that minimizes the population-average regulator cost given `F̂` and `γ̂(x), ψ̂(x)`.
2. Recompute `θ̄* = ē(1) − ē(0)` (`c = 1`).
3. Predict each CWS's new `Pr(B = 1) = 1 − F̂(θ̄*|x_i)`.

**Reported.** %Δ violation incidence, %Δ enforcement spending, %Δ total social cost.

### CF2 — Equalized regulator preferences (the EJ counterfactual)

**Question.** What if the regulator weighted mining-exposed and non-mining-exposed CWSs identically?

**Computation.**
1. Replace `γ̂(x_i)` with `γ̂(x̃_i)` where `x̃_i` sets mining components to the non-mining sample mean. Same for `ψ̂`.
2. Re-solve regulator FOC for the new `θ*_eq(x̃_i)`.
3. Compute new `Pr(B = 1 | x_i) = 1 − F̂(θ*_eq | x_i)`.

**Reported.** Δ violation incidence, Δ days-to-RTC, Δ population-weighted exposure, by HUC mining quartile. **Headline result.**

### CF3 — First-best (`ψ = 0`)

**Question.** Distance from costless-enforcement benchmark.

**Computation.** Set `ψ(x) = 0`, re-solve. With `ψ = 0` the FOC collapses to `γ(x) = θ*(x)`, i.e., regulator sets the threshold at perceived marginal harm.

### CF4 — "Green regulator" upper bound

**Question.** Upper bound on violations attributable to regulator under-weighting of mining-exposed CWSs.

**Computation.** Set `γ̂(x_i) ≡ γ̄ = max_i γ̂(x_i)` and `ψ̂(x_i) ≡ ψ_min = min_i ψ̂(x_i)`. Re-solve.

### CF5 — No-mining counterfactual

**Question.** Equilibrium MR violations and SDWA enforcement if mining were eliminated, accounting for regulator re-tailoring.

**Computation.**
1. `x̃_it`: set mining variables to zero; leave sulfur and demographics unchanged.
2. Recompute `γ̂(x̃)`, `ψ̂(x̃)` from Eq. 7 (linear projection).
3. Solve regulator FOC for new `θ*_nm(x̃_i)`.
4. Compute `Pr(B = 1 | x̃)` from `F̂(·|x̃)`.

**Reported.**
- Δ violation incidence by HUC type (mine / upstream / downstream).
- Δ enforcement intensity faced by each CWS.
- Decomposition: total Δ = (Δ from `F(·|x)` shift at fixed `e`) + (Δ from regulator re-tailoring `e`).

The decomposition separates the *direct* effect of mining on type distribution from the *equilibrium* effect of mining on regulator allocation.

### CF Validation — out-of-sample structural-stability test

Estimate Eqs. 4–5 on the bottom three IV-residual quartiles. Predict `p(x)` for the top quartile. Compare predicted to observed. Close fit validates the structural assumption that the primitives are stable functions of `x`.

---

## 9. Feasibility Checks Required Before Coding

The three §9 checks from the continuous variant have already been run (§15). Two of the three are still relevant for the binary variant; one is replaced. The remaining tests, implemented in `binary_feasibility.r`:

1. **Variance of `Δê(x)` across IV-bins.** The binary threshold `θ*(x) = Δê(x)` is the lever for identifying `F(·|x)`. If `Δê(x)` is nearly constant across `x`-bins, the GMM moment system in Eq. 4 is rank-deficient and `F` is not identified at multiple θ points. Quantify by regressing `Δê(x)` on `x` (and `z`) and reporting the R² and across-bin standard deviation.
2. **Monotonicity of `p̂(x)` in the IV.** The binary analogue of LPV stochastic ordering. Pull `p̂(x)` from Eq. 3 (or the raw bin means of `B`), and test whether it is monotone in the IV across quartiles. Q3 → Q4 was where Check 3 of the continuous version broke (FOSD share 9%); we need to know whether that survives the discrete recasting.

**Inherited from the continuous version:**

- **Enforcement responds to action (Check 2 of §15).** Re-run with `B` instead of `K` and `K²`. Expect `φ_B` to be highly significant given that Check 2 already passed with the linear-in-`K` slope.

---

## 10. Differences from Kang and Silveira

| Dimension | K&S 2021 | This proposal (binary) |
|---|---|---|
| Setting | California NPDES wastewater | Federal SDWA drinking water |
| Firm | 288 wastewater plants | 340 CWSs |
| Violation | Effluent count, observed monetarily | MR violation indicator, 365-day binary |
| Penalty | Dollar amount per violation | Two-point: `(e(0\|x), e(1\|x))` = Pr × duration |
| Type θ | Compliance cost | CWS compliance cost (set-identified at unit level) |
| Identification regime | 2 penalty regimes (pre/post 2006) | 1 regime + IV on `x` |
| Identification machinery | T^H, T^V transforms | Probit threshold + cross-bin GMM |
| Time structure | Static | Static |
| Choice | Continuous a | Binary `B ∈ {0, 1}` |
| Primitives | F, b', γ, ψ | F (parametric), c (normalized), γ, ψ |
| Counterfactuals | 4 (uniform, linear, first-best, green) | 5 (above + no-mining decomposition) |
| Main risk | n/a | IV exclusion + monotonicity of `p̂(x)` in IV |
| Target venue | JPE | JPubEcon / AEJ:Applied |

---

## 11. Differences from the Earlier Dynamic CCP Plan

| Dimension | Dynamic CCP (earlier plan) | Binary K&S static (this proposal) |
|---|---|---|
| Time | Dynamic, β = 0.95 | Static |
| Choice | Binary {comply, MR} | Binary {comply, MR} |
| Identification | 2-state machine + control function | Probit + cross-bin GMM + IV |
| Primitives recovered | `k_MR` only | `F(·\|x)`, γ(x), ψ(x), c (=1) |
| Main risk | Cell-level aggregation mismatch | IV monotonicity of `p̂(x)` |
| Counterfactual menu | Doubled enforcement, validation, level comparison | Uniform, EJ-equalization, first-best, green, no-mining |
| Identification source | 2-state machine + control function | Cross-`x`-bin moment system + IV |
| Main story | "`k_MR` shows enforcement is/isn't deterring" | "γ(x) shows regulator under-weights mining areas" |
| Aggregation problem | Yes (8 cells, LHS constant) | No (PWSID×year level throughout) |
| Dynamic deterrence story | Yes | No |
| Regulatory machine framing | Required, awkward | Not required |

---

## 12. Tradeoffs

**What this proposal gives up vs. the continuous K&S adaptation.**
- `b'(a)` is no longer identified as a curve — it collapses to a single scale `c` normalized to 1.
- `F(·|x)` is parametric (log-normal), not nonparametric. The LPV machinery is not used.
- Firm-level `θ_i` is only set-identified (interval per unit).

**What it keeps relative to that adaptation.**
- The regulator-preference primitives `γ(x), ψ(x)`, including the EJ test.
- The no-mining counterfactual CF5.
- The IV exclusion restriction is the only structural identification assumption, same as the continuous version.

**What it gains relative to the dynamic CCP plan.**
- No aggregation mismatch — estimation is at PWSID×year throughout.
- A second structural object (γ vs. ψ) instead of one (`k_MR`).
- A real CF5 counterfactual.
- A cleaner identification story; no Bellman, no regulatory machine.

**What it gives up relative to the dynamic CCP plan.**
- No dynamic deterrence story.

---

## 13. Next Steps

1. Run `binary_feasibility.r` (§9). The first execution is reported in §16 below.
2. If feasibility passes, draft `code/coal_mining_water_quality/structural_ks_binary.r` following the pseudocode in §7.
3. Estimate Eqs. 1–3 first; report sanity checks (first-stage F, predicted enforcement burden, probit fit).
4. Implement Eq. 4 (cross-bin GMM for `F`) — this is the lift; budget ~1–2 weeks given the simpler identification.
5. Implement Eq. 5 (regulator FOC NLS) — ~3 days.
6. Bootstrap SEs (resample PWSIDs, redo the pipeline; 500 reps).
7. Counterfactuals CF1–CF5 and the validation exercise.

---

## 14. Open Questions

- Parametric form for `F(·|x)`: log-normal vs. Weibull vs. Gumbel. Report sensitivity.
- Should `x`-bins be quartiles of the IV value, of the IV residual, or of the first-stage prediction? Each gives slightly different cross-bin variation.
- Pool across mining-related contaminants (one `B_it`) or estimate separately for each? With binary outcomes, sparsity may force pooling regardless.
- Bin count `K`: 4 vs. 8. More bins means more moments but smaller bins. K = 4 is the conservative starting choice.

---

## 15. Feasibility Evidence That Motivated This Version (2026-05-22)

Script: [code/coal_mining_water_quality/ks_static_feasibility.r](../../code/coal_mining_water_quality/ks_static_feasibility.r)
Sample: 6,232 obs, 340 CWSs (downstream-only, 1985–2005, WV3303401 dropped).

| Check | Result | Verdict |
|---|---|---|
| 1. Poisson/NB dispersion of `K_it` | mean = 40.1, var = 13,019, var/mean = **325**. 89.0% of obs `K = 0`; of the 10.98% nonzero obs, **every decile equals 365**. NB θ = 6.0×10⁵ (unstable). | **FAIL for continuous K&S.** `K` is effectively Bernoulli. Motivates the binary recasting. |
| 2. Enforcement responds to `K` | `φ₁ = 0.00315`, t = 21.3. `K²` dropped (rank-deficient — `K` is near-binary). `Pr̂(E=1)`: 0.19 at `K=0` → 0.23 at mean → 0.61 at `K=365`. Wald χ² = 454. | **PASS.** Enforcement has clear deterrence content; survives the recasting to `B`. |
| 3. LPV monotonicity across IV-bins | FOSD share: Q2 > Q1 100%, Q3 > Q1 100%, Q4 > Q1 100%, Q3 > Q2 100%, Q4 > Q2 100%, **Q4 > Q3 only 9%**. | **PARTIAL FAIL.** Lower three bins ordered; Q4 < Q3 on `K`. Replaced for the binary version by monotonicity of `p̂(x)`. |

### Implications

- The Bernoulli structure of `K` (Check 1) made the continuous-action K&S non-identifiable.
- Check 2 says SDWA enforcement has deterrence content the firm responds to — keep the firm FOC story.
- Check 3 needs to be re-asked in binary terms: does `p̂(x) = Pr(B = 1 | x)` move monotonically in the IV across the top of the support? This is what `binary_feasibility.r` tests (§16).

---

## 16. Binary-Variant Feasibility Results (2026-05-22)

Script: [code/coal_mining_water_quality/binary_feasibility.r](../../code/coal_mining_water_quality/binary_feasibility.r)
Figure: [output/fig/binary_feasibility_p_hat_by_iv.png](../../output/fig/binary_feasibility_p_hat_by_iv.png)
Sample: 6,232 obs, 340 CWSs; share `B = 1` is 10.98%.

| Check | Result | Verdict |
|---|---|---|
| 1. `Pr(E = 1)` responds to `B` | Probit `φ_B = 1.151`, t = 21.33 (p ≈ 6e-101). Predicted `Pr(E=1)`: 0.189 at `B = 0` → 0.606 at `B = 1`. `ξ_B = 1.180` (t = 16.7) for log days-to-RTC. | **PASS.** Enforcement schedule has strong, deterministic deterrence content on the binary margin. Two-point penalty `(ê(0\|x), ê(1\|x))` is well-estimated. |
| 2. Cross-IV-bin variation in `Δê(x)` | At quartile medians: 146.0 / 129.9 / 133.7 / 129.9 days; mean 134.9, sd 7.64, **CV = 0.057**. Q1 (low-IV) sits ~12% above the cluster Q2-Q4. At the panel level (full `x` heterogeneity): `Δê` has sd = 18.4, p10–p90 = [109.7, 146.4]. | **MARGINAL.** Cross-bin variation in `Δê(x)` is small (~5–6%) when bins are summarized at their median `x`. Panel-level `x` heterogeneity gives larger spread. GMM moment system in Eq. 4 will be weakly identified at the bin-center level — consider using individual observations (not bin medians) as moment contributions, or finer bin definitions (e.g., interact IV-quartile with mining quartile). |
| 3. `p̂(x) = Pr(B = 1 \| x)` monotone in IV | Linear trend across quartiles: +0.016, **t = 3.28**. Raw bin means (Q1→Q4): 0.092, 0.100, 0.156, **0.125** — Q3 → Q4 dips (the same break point as the continuous Check 3). Fitted probit `p̂(x)` (with `v̂` and controls): 0.072, 0.101, 0.124, **0.180** — **strictly monotone**. | **PASS.** The probit, conditioning on `v̂` and `x` controls, recovers monotonicity. This is what enters Eq. 4. The raw-bin-mean inversion at Q4 reflects compositional differences in `x` that the probit absorbs. |

### Verdict

The binary-choice variant is feasible. The two relevant checks pass; the marginal one (cross-bin `Δê` variance at bin centers) is workable but flags a design choice: estimate Eq. 4 using individual-observation moments rather than bin-median moments, and verify identification by reporting GMM moment-condition rank / minimum-eigenvalue diagnostics at estimation time.

### Implications for §7 pseudocode

- **Eq. 4 implementation:** use observation-level moments `F(Δê(x_it) | x_it) = 1 − E[B_it | x_it, v̂_it]` rather than bin-level moments. The bin-level summary is for diagnostic display; identification leverages full `x` heterogeneity.
- **Eq. 5 stays as written** — γ(x), ψ(x) parametrized linearly in `x` and estimated by NLS on bin-level FOC residuals.
- **Bootstrap SEs:** required given the marginal cross-bin variation. Resample PWSIDs and redo Eqs. 1–5; report standard errors and percentile intervals.

### Next concrete step

Write `code/coal_mining_water_quality/structural_ks_binary.r` per §7 with the Eq. 4 moment-condition change above. Budget ~2 weeks to first draft of Eqs. 1–5; ~1 week for counterfactuals; bootstrap is overnight wall-time once code is debugged.
