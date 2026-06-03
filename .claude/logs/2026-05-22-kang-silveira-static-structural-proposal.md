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
- Compliance saving: `θ·c`, where `c = b(0) − b(1) > 0` is the gross resource saving from non-compliance. `b(·)` is a **common** effort function — the same for all CWSs; `θ_i` is the idiosyncratic scaling. Normalize `c = 1` (scale normalization: only the product `θ·c` appears in the model, so the scale of `θ` and `c` are not separately identified; K&S impose the equivalent normalization by pinning the **type** `θ̃(a₀, post) = 1` at a reference action — Proposition 2 and fn. 33, p. 2972 of JPE; they do **not** normalize `b'(a₀) = 1`).

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
4. **Regulator preferences `γ(x), ψ(x)`.** Plug `θ̂*(x_it) = Δê(x_it)`, `F̂(θ̂*|x_it)`, `f̂(θ̂*|x_it)` into the regulator FOC at every observation `it`. Parametrize `log γ(x) = w_it'·β_γ` and `log ψ(x) = w_it'·β_ψ`. Estimate `(β_γ, β_ψ)` by NLS minimizing the sum of squared FOC residuals across all observations. The FOC is a structural restriction that must hold at every x, so every observation contributes a moment — overidentification is by N − 2K and lets us run a J-test for misspecification. The bin-level NLS variant (K = 4 IV-quartiles) is retained as a robustness column.

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

**Enforcement (regulator action) — formal/informal split (updated 2026-06-01).**

From `SDWA_VIOLATIONS_ENFORCEMENT.csv`, filtered to enforcement subsample (268 PWSIDs with any enforcement record, 1985–2005):

| Variable | Definition | Obs in sample | Pr(=1\|B=1) | Pr(=1\|B=0) |
|---|---|---|---|---|
| `formal_enf_it` | Any formal SDWA enforcement action that year (SFJ, SFL, SFM, SFO, SFQ, SFR, EFL, …) | 218 PWSID-years | 10.2% | 2.7% |
| `informal_enf_it` | Any informal enforcement action that year (SIA, SIB, SIC, SID, …) | ~2,100 PWSID-years | 57.5% | 14.3% |
| `days_to_RTC_it` | Days from violation onset to return-to-compliance, by enforcement type | 771 obs for formal; ~4,500 for informal | — | — |

The dominant formal action is **SFR (State Consent Decree/Judgement)**. The B-conditional gap is strong for both types (ratio ~3.8× for formal, ~4.0× for informal), supporting probit identification of φ_B in both Eqs. 2a.

**Sanitary surveys (monitoring intensity covariate).**
From `SDWA_SITE_VISITS.csv` (SNSV, SNSP, L1SS, L2SS, SSVF codes):
- `any_snsv_it = 1` if any sanitary survey visit in that PWSID-year. N = 910 PWSID-years, 270 PWSIDs.
- Survey rate: 14.04% when B=1, 14.62% when B=0 — essentially no B-conditional gap.
- Sanitary surveys are scheduled inspections, not violation-triggered enforcement. They enter **W** as a monitoring-intensity covariate for F(θ|x), not Δê.

**Covariates `x_it`.**
- `num_facilities`, `POPULATION_SERVED_COUNT`, `OWNER_TYPE_CODE`, `PRIMARY_SOURCE_CODE`, `sulfur_unified`, `any_snsv`, plus state and year fixed effects.

### 4.3 Data quality caveats

- **MCL violations remain too sparse for separate structural treatment.** Only 4.4% of downstream CWSs ever report an MCL violation in mining-related contaminants. Model is restricted to MR margin.
- **Penalty amounts are not in dollars.** The regulator's "expected penalty" is reconstructed from `Pr(enforcement type) × E[days-to-RTC | enforcement type]`, separately for formal and informal actions.
- **Relative deterrence κ is not directly observed.** The weight of informal vs formal enforcement is estimated as a free parameter (κ) in Eq. 4's pseudo-likelihood. Primary spec sets κ = 0 (formal only); κ free is a robustness column.

---

## 5. Estimating Equations

Notation: `i` = CWS, `t` = year. `x_it` = covariates. `z_it` = `post95 × sulfur_unified`. `B_it` = MR-violation indicator. `E_it` = enforcement indicator.

### Equation 1 — First stage / control function

```
m_it = π·z_it + x_it'·ρ + η_i + τ_t + ν_it
```

Save `v̂_it`. The exclusion restriction is the standard 2SLS one.

### Equation 2 — Enforcement burden by action and `x` (updated 2026-06-01)

Estimate **four** equations on the enforcement subsample. Mining (`log(1+m_it)`) enters all four, allowing Δê to vary with mining exposure — the key channel for the EJ enforcement laxity finding (h3 2SLS: formal enforcement −0.087\*\*\* on `num_coal_mines_upstream`).

**Formal enforcement equations** (111 PWSIDs, 218 PWSID-years positive):
```
(2a_formal)  Pr(E_formal_it = 1 | B_it, x_it, v̂_it) = Φ(φ₀ + φ_B·B_it + φ_m·log(1+m_it) + x_it'·φ_x + φ_v·v̂_it)
(2b_formal)  log(days_to_RTC_it + 1) | E_formal = 1  = ξ₀ + ξ_B·B_it + ξ_m·log(1+m_it) + x_it'·ξ_x + u_it
```

**Informal enforcement equations** (267 PWSIDs, ~2,100 PWSID-years positive):
```
(2a_informal)  Pr(E_informal_it = 1 | B_it, x_it, v̂_it) = Φ(ψ₀ + ψ_B·B_it + ψ_m·log(1+m_it) + x_it'·ψ_x + ψ_v·v̂_it)
(2b_informal)  log(days_to_RTC_it + 1) | E_informal = 1 (& E_formal = 0)  = ζ₀ + ζ_B·B_it + ζ_m·log(1+m_it) + x_it'·ζ_x + u_it
```

Expected signs: `φ_m < 0` (EJ enforcement laxity — less formal enforcement in mining areas, consistent with h3 2SLS); `ψ_m ≥ 0` (informal enforcement neutral or higher in mining areas).

Construct type-specific two-point schedules and the composite Δê:

```
ê_formal(B | x)   = Pr̂(E_formal = 1 | B, x) · Ê[days_to_RTC | E_formal = 1, B, x]
ê_informal(B | x) = Pr̂(E_informal = 1 | B, x) · Ê[days_to_RTC | E_informal = 1, B, x]

Δê_formal(x)   = ê_formal(1 | x) − ê_formal(0 | x)
Δê_informal(x) = ê_informal(1 | x) − ê_informal(0 | x)

Δê(x) = Δê_formal(x) + κ · Δê_informal(x)
```

`κ ∈ [0,1]` = relative deterrence weight of informal vs formal enforcement.
**Primary spec:** `κ = 0` (formal enforcement only drives the threshold — most conservative and structurally cleanest).
**Robustness:** `κ` estimated jointly as a free scalar in Eq. 4's pseudo-likelihood.

With `c = 1`, the firm threshold is `θ̂*(x) = Δê(x) = Δê_formal(x)` (primary spec).

### Equation 3 — Compliance probability (firm side, diagnostic only)

```
p̂(x_it) = Pr(B_it = 1 | x_it, v̂_it) = Φ(α₀ + α_m·log(1 + m_it) + α_s·sulfur_it + x_it'·α_x + α_v·v̂_it)
```

**Demoted to a diagnostic** as of the Option C switch (see Eq. 4 below). Used for: (i) §16 Check 3 — verifying `p̂(x)` is monotone in the IV; (ii) the robustness column comparing Option B (NLS on `1 − p̂`) against Option C (pseudo-likelihood); (iii) the model-fit check `1 − F̂(Δê(x_it)|x_it)` vs `p̂(x_it)` after estimation. Not on the main estimation path for `F(·|x)`.

### Equation 4 — Type distribution `F(·|x)` via pseudo-likelihood (Option C)

Parametrize log-normal:

```
log θ | x ~ N(μ(x), σ²(x)),     μ(x) = w_it'·δ_μ,  log σ(x) = w_it'·δ_σ.
```

Under the structural model `B_it = 1{θ_it ≥ Δê(x_it)}`, so

```
Pr(B_it = 1 | x_it) = 1 − Φ( η_it ),    η_it = [log Δê(x_it) − w_it'·δ_μ] / exp(w_it'·δ_σ).
```

Estimate `(δ_μ, δ_σ)` by maximizing the binary-outcome pseudo-likelihood

```
ℓ(δ) = Σ_it { B_it · log[1 − Φ(η_it)] + (1 − B_it) · log[Φ(η_it)] }.
```

This is a probit with `log Δê(x_it)` as a **known offset** (where `Δê = Δê_formal` in the primary spec) and `w_it` (which includes `v̂_it` and `any_snsv_it` for monitoring intensity) entering μ and log σ. Uses raw `B_it` rather than the smoothed `p̂(x_it)`, avoiding propagation of Eq. 3 prediction error. PWSID-clustered bootstrap for SEs (resample PWSIDs, redo Eqs. 1, 2a_formal, 2a_informal, 2b_formal, 2b_informal, 4, 5; 500 reps).

**W matrix (updated 2026-06-01):**
```
w_it = [1, log(1+m_it), sulfur_it, num_facilities_it, log(pop_it+1),
        factor(OWNER_TYPE_CODE), factor(PRIMARY_SOURCE_CODE),
        factor(state), any_snsv_it, v̂_it]
```
`any_snsv_it` controls for monitoring intensity — survey frequency affects compliance cost distributions independently of the enforcement schedule.

**Identification.** The same cross-`it` heterogeneity in `(B_it, Δê(x_it), w_it)` that would identify the original bin-level GMM identifies the pseudo-likelihood. The switch is an estimator change (MLE vs NLS/GMM on residual), not an identification change. Motivated by §16: cross-IV-bin variation in `Δê` is only ~6%, but observation-level variation has sd 18.4 days and p10–p90 = [109.7, 146.4] — Option C uses the full panel-level spread.

**Robustness alternatives reported as table columns:**
- Option A: GMM with PWSID-clustered HAC weight on moments `g_it = F(Δê(x_it)|x_it;δ) − (1−p̂(x_it))`.
- Option B: NLS — `δ̂ = argmin Σ_it [F(Δê(x_it)|x_it;δ) − (1−p̂(x_it))]²`. Equivalent to A with identity weight.
- Option C (primary): pseudo-likelihood as above.

### Equation 5 — Regulator FOC system (observation-level NLS)

At every observation `it`, the regulator FOC implies the residual

```
r_it(β_γ, β_ψ) = exp(w_it'·β_γ)
               − Δê(x_it) · (1 + exp(w_it'·β_ψ))
               − exp(w_it'·β_ψ) · (1 − F̂(Δê(x_it)|x_it)) / f̂(Δê(x_it)|x_it).
```

Estimate

```
(β̂_γ, β̂_ψ) = argmin Σ_it r_it(β_γ, β_ψ)².
```

Log-link parametrizations `log γ(x) = w_it'·β_γ` and `log ψ(x) = w_it'·β_ψ` keep γ, ψ > 0. With N = 6,232 observations and 2K parameters, the system is overidentified by N − 2K. Report the Hansen J-statistic as a misspecification test. PWSID-clustered bootstrap for SEs (resample PWSIDs, redo Eqs. 1, 2a_formal, 2a_informal, 2b_formal, 2b_informal, 4, 5).

`Δê(x_it)` in the FOC residual uses the formal-only schedule (primary spec), so φ_m from Eq. 2a_formal feeds directly into the regulator primitive identification: where formal enforcement is lower (mining areas), the threshold θ\* is lower, which changes the hazard term and thus the estimated γ and ψ.

**Practical issues to flag in implementation:**

- *Hazard tail*: `(1 − F̂)/f̂` can explode in the right tail of the log-normal. Diagnose with `summary(hazard)` and winsorize if extreme values dominate the NLS objective.
- *Regulator-side `w_it`*: should arguably exclude the firm-side CF residual `v̂_it` — the regulator's preferences over harm reduction don't depend on first-stage residuals from a mining-exposure regression. Document the choice; report both inclusions as robustness.

**Robustness alternative:** bin-level NLS with `k = 1, …, K = 4` IV-quartiles (the original §5 formulation). Reported alongside the observation-level estimates.

### Equation 6 — Recovered firm-level compliance cost (plug-in)

```
θ̂_it = Δê(x_it)   if B_it = 1   (lower bound on θ)
θ̂_it ≤ Δê(x_it)   if B_it = 0   (upper bound)
```

In the discrete-action setting `θ_i` is only set-identified at the unit level. Distributional statements use `F̂(·|x)` directly.

### Equation 7 — Regulator EJ tests

Under observation-level Eq. 5 with `log γ(x) = w_it'·β_γ`, the EJ coefficients are **already inside `β̂_γ`** at the positions corresponding to mining and sulfur. Reading them off directly:

```
α_m = β̂_γ[mining];   α_s = β̂_γ[sulfur]
μ_m = β̂_ψ[mining];   μ_s = β̂_ψ[sulfur]
```

`α_m < 0` ⟹ regulator perceives lower marginal harm per MR violation in mining-exposed CWSs. This is the headline EJ test.

**Inference.** Use the PWSID-clustered bootstrap distribution of `β̂_γ`, `β̂_ψ` from the full Eqs. 1–5 pipeline (500 reps). Report point estimates with percentile intervals and signed one-sided p-values for the EJ hypothesis.

**Honest framing.** Eq. 7 is a *reading off* of structural coefficients, not an independent regression on recovered `γ̂(x_it)`. The earlier two-step formulation (regress `log γ̂(x_it)` on mining covariates separately) was redundant once Eq. 5 already parametrizes log γ linearly in x. Reporting `β̂_γ`, `β̂_ψ` directly is the cleanest presentation.

---

## 6. Data → Estimator → Output

| Step | Input data | Estimator | Output |
|---|---|---|---|
| Eq. 1 | Full panel | OLS (`feols`) | `v̂_it` |
| Eq. 2a_formal | Enforcement panel (111 PWSIDs with formal actions) | Probit | Pr̂(E_formal=1 \| B, m, x) |
| Eq. 2b_formal | Formal E=1 subset (771 obs with RTC) | OLS (`feols`) | Ê[days_to_RTC \| E_formal=1, B, m, x] |
| Eq. 2a_informal | Enforcement panel (267 PWSIDs with informal actions) | Probit | Pr̂(E_informal=1 \| B, m, x) |
| Eq. 2b_informal | Informal E=1 subset (E_formal=0) | OLS (`feols`) | Ê[days_to_RTC \| E_informal=1, B, m, x] |
| Eq. 2 | Outputs of 2a/2b by type | Construction | `Δê_formal(x)`, `Δê(x) = Δê_formal + κ·Δê_informal` |
| Eq. 3 (diagnostic) | Full panel | Probit with CF correction | `p̂(x)` — §16 Check 3 and robustness only |
| Eq. 4 | Full panel: `B_it`, `Δê_formal(x_it)`, `w_it` (incl. `any_snsv`) | Pseudo-likelihood MLE (probit with `log Δê_formal` offset) | `δ_μ`, `δ_σ` ⟹ `F̂(·\|x)` |
| Eq. 5 | Full panel `(Δê_formal(x_it), F̂, f̂)` | NLS on observation-level FOC residuals | `β̂_γ`, `β̂_ψ` ⟹ `γ̂(x)`, `ψ̂(x)` |
| Eq. 6 | Plug-in | — | Set bounds on `θ_i` |
| Eq. 7a/b | `β̂_γ`, `β̂_ψ` from Eq. 5 (mining/sulfur components) | Read off + PWSID-clustered bootstrap | `α_m`, `α_s`, `μ_m`, `μ_s` |

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

# --- Eq. 2: enforcement schedule — formal/informal split (updated 2026-06-01) ---
# Load enforcement file; construct separate formal and informal annual indicators.
# Mining (log(1+m)) enters both 2a and 2b so Δê varies with mining exposure.

# formal_enf: ENF_ACTION_CATEGORY == "Formal" (SFJ/SFL/SFM/SFO/SFQ/SFR/EFL/...)
# informal_enf: ENF_ACTION_CATEGORY == "Informal" (SIA/SIB/SIC/SID/...)
# any_snsv: VISIT_REASON_CODE %in% c("SNSV","SNSP","L1SS","L2SS","SSVF") from SDWA_SITE_VISITS.csv
# — any_snsv enters W (monitoring intensity covariate) but NOT Δê (no B-conditional gap: 14.0% vs 14.6%)

# Eq. 2a_formal: probit for formal enforcement
fit_2a_formal <- glm(formal_enf ~ B + log(1 + num_coal_mines_upstream) +
                       num_facilities + POPULATION_SERVED_COUNT +
                       factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
                       factor(state) + v_hat,
                     family = binomial("probit"), data = enf_panel)

# Eq. 2a_informal: probit for informal enforcement
fit_2a_informal <- glm(informal_enf ~ B + log(1 + num_coal_mines_upstream) +
                         num_facilities + POPULATION_SERVED_COUNT +
                         factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
                         factor(state) + v_hat,
                       family = binomial("probit"), data = enf_panel)

# Eq. 2b_formal: log days-to-RTC | formal enforcement = 1
fit_2b_formal <- feols(log(days_to_RTC + 1) ~ B + log(1 + num_coal_mines_upstream) +
                         num_facilities + POPULATION_SERVED_COUNT |
                         OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
                       data = filter(enf_panel, formal_enf == 1, !is.na(days_to_RTC)))

# Eq. 2b_informal: log days-to-RTC | informal only (not formal) = 1
fit_2b_informal <- feols(log(days_to_RTC + 1) ~ B + log(1 + num_coal_mines_upstream) +
                           num_facilities + POPULATION_SERVED_COUNT |
                           OWNER_TYPE_CODE + PRIMARY_SOURCE_CODE,
                         data = filter(enf_panel, informal_enf == 1, formal_enf == 0, !is.na(days_to_RTC)))

# Construct Δê_formal and Δê_informal at panel level
# Primary spec: κ = 0 (formal enforcement only drives threshold θ*)
panel$e_formal_B0 <- predict(fit_2a_formal,   newdata = cbind(B=0L, panel_pred), type="response") *
                     (exp(predict(fit_2b_formal,   newdata = cbind(B=0L, panel_pred))) - 1)
panel$e_formal_B1 <- predict(fit_2a_formal,   newdata = cbind(B=1L, panel_pred), type="response") *
                     (exp(predict(fit_2b_formal,   newdata = cbind(B=1L, panel_pred))) - 1)
panel$Delta_e_formal <- pmax(panel$e_formal_B1 - panel$e_formal_B0, 1e-6)

panel$e_informal_B0 <- predict(fit_2a_informal, newdata = cbind(B=0L, panel_pred), type="response") *
                       (exp(predict(fit_2b_informal, newdata = cbind(B=0L, panel_pred))) - 1)
panel$e_informal_B1 <- predict(fit_2a_informal, newdata = cbind(B=1L, panel_pred), type="response") *
                       (exp(predict(fit_2b_informal, newdata = cbind(B=1L, panel_pred))) - 1)
panel$Delta_e_informal <- pmax(panel$e_informal_B1 - panel$e_informal_B0, 1e-6)

# Primary Δê: formal only (κ = 0); robustness: κ estimated in pseudo-likelihood
kappa <- 0   # set to 0 for primary; estimate via nlminb for robustness
panel$Delta_e     <- panel$Delta_e_formal + kappa * panel$Delta_e_informal
panel$log_delta_e <- log(panel$Delta_e)

# --- Eq. 3 (DIAGNOSTIC ONLY): compliance probability ---
# Used for §16 Check 3 (monotonicity of p̂ in IV) and as Option B robustness input.
# Not on the main estimation path for F(·|x).
fit_3 <- glm(B ~ log(1 + num_coal_mines_upstream_mean) + sulfur_unified_mean +
               num_facilities + POPULATION_SERVED_COUNT +
               factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) + v_hat,
             family = binomial("probit"), data = panel)

# --- Eq. 4: F(θ|x) via pseudo-likelihood (Option C) ---
# Probit with log(Δê) as a known offset; w_it parametrizes μ(x) and log σ(x).
# Identification: cross-it variation in (B_it, Δê(x_it), w_it).
panel$log_delta_e <- log(sapply(seq_len(nrow(panel)), function(i) Delta_e_hat(panel[i, ])))

# w_it: covariates for F(·|x). Includes state FEs, any_snsv (monitoring intensity), v_hat.
W <- model.matrix(~ log(1 + num_coal_mines_upstream) + sulfur_unified +
                    num_facilities + log(POPULATION_SERVED_COUNT + 1) +
                    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
                    factor(state) + any_snsv + v_hat,
                  data = panel_cc)
K <- ncol(W)

loglik <- function(par) {
  delta_mu    <- par[1:K]
  delta_sigma <- par[(K + 1):(2 * K)]
  mu_it       <- as.numeric(W %*% delta_mu)
  sigma_it    <- exp(as.numeric(W %*% delta_sigma))
  eta_it      <- (panel$log_delta_e - mu_it) / sigma_it
  p1          <- pnorm(eta_it, lower.tail = FALSE)   # Pr(B = 1 | x) = 1 - Φ(η)
  p1          <- pmin(pmax(p1, 1e-12), 1 - 1e-12)
  -sum(panel$B * log(p1) + (1 - panel$B) * log(1 - p1))
}

start <- c(rep(0, K), rep(log(0.5), K))
fit_4 <- nlminb(start, loglik)
delta_mu_hat    <- fit_4$par[1:K]
delta_sigma_hat <- fit_4$par[(K + 1):(2 * K)]

# Helper closures for downstream use (Eq. 5 and counterfactuals).
mu_of    <- function(W_new) as.numeric(W_new %*% delta_mu_hat)
sigma_of <- function(W_new) exp(as.numeric(W_new %*% delta_sigma_hat))
F_of     <- function(theta, W_new) plnorm(theta, mu_of(W_new), sigma_of(W_new))
f_of     <- function(theta, W_new) dlnorm(theta, mu_of(W_new), sigma_of(W_new))

# Model-fit diagnostic: compare 1 - F̂(Δê|x) (structural) to p̂ from Eq. 3.
panel$p_hat_struct <- 1 - F_of(exp(panel$log_delta_e), W)
panel$p_hat_eq3    <- predict(fit_3, type = "response")
# cor(panel$p_hat_struct, panel$p_hat_eq3) should be high if F is well-specified.

# --- Eq. 5: γ(x), ψ(x) via observation-level NLS on FOC residuals ---
# w_it: regressors for log γ and log ψ. By default use the same covariates as in W
# (the Eq. 4 design matrix). Consider dropping v_hat from the regulator side —
# regulator preferences need not depend on the firm-side first-stage residual.
W_reg <- W
K_reg <- ncol(W_reg)

theta_star <- exp(panel$log_delta_e)            # Δê(x_it) on the levels scale
F_pts <- F_of(theta_star, W)                    # closures from fit_4
f_pts <- f_of(theta_star, W)
hazard <- (1 - F_pts) / pmax(f_pts, 1e-12)      # guard against f → 0 in the tail

# Diagnostic: hazard tail behavior
summary(hazard); quantile(hazard, c(0.95, 0.99, 1.00))

foc_resid_obs <- function(par) {
  beta_gamma <- par[1:K_reg]
  beta_psi   <- par[(K_reg + 1):(2 * K_reg)]
  gamma_it   <- exp(as.numeric(W_reg %*% beta_gamma))
  psi_it     <- exp(as.numeric(W_reg %*% beta_psi))
  resid      <- gamma_it - theta_star * (1 + psi_it) - psi_it * hazard
  sum(resid^2)
}

start_5 <- c(rep(0, K_reg), rep(0, K_reg))
fit_5   <- nlminb(start_5, foc_resid_obs)
beta_gamma_hat <- fit_5$par[1:K_reg]
beta_psi_hat   <- fit_5$par[(K_reg + 1):(2 * K_reg)]

# Hansen J-stat at the converged residuals (misspecification check, overid by N - 2K).
# Implement as N * resid' Ŵ resid with Ŵ = (cluster-robust moment variance)^-1.

panel$gamma_hat <- exp(as.numeric(W_reg %*% beta_gamma_hat))
panel$psi_hat   <- exp(as.numeric(W_reg %*% beta_psi_hat))

# --- Eq. 7: EJ tests — read off β̂_γ, β̂_ψ from Eq. 5 ---
# Under observation-level Eq. 5 with log γ(x) = w'β_γ, the EJ coefficients ARE
# β̂_γ at the mining/sulfur positions. No separate regression needed.
ej_table <- data.frame(
  param = colnames(W_reg),
  beta_gamma = beta_gamma_hat,
  beta_psi   = beta_psi_hat
)
# EJ headline test: ej_table[grep("upstream|sulfur", ej_table$param), ]

# Bootstrap SE: resample PWSIDs, redo Eqs. 1, 2a, 2b, 4, 5; store β̂_γ, β̂_ψ; 500 reps.
# Percentile intervals on the mining/sulfur components are the EJ test.

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
| Penalty | Dollar amount per violation | Two-point: `(e(0\|x), e(1\|x))` = Pr(formal enforcement) × duration; κ-weighted composite with informal as robustness |
| Type θ | Compliance cost | CWS compliance cost (set-identified at unit level) |
| Identification regime | 2 penalty regimes (pre/post 2006) | 1 regime + IV on `x` |
| Identification machinery | T^H, T^V transforms | Probit threshold + cross-bin GMM |
| Time structure | Static | Static |
| Choice | Continuous a | Binary `B ∈ {0, 1}` |
| Primitives | F, b', γ, ψ | F (parametric), c = 1 (scale norm, analogous to K&S type norm θ̃(a₀)=1 not b'(a₀)=1), γ, ψ |
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

1. ~~Run `binary_feasibility.r` (§9).~~ **Done** — see §16.
2. ~~Draft `structural_ks_binary.r` per §7 pseudocode.~~ **Done** — initial version written and test-run 2026-06-01.
3. ~~Implement Eqs. 1–5, bootstrap, counterfactuals.~~ **Done** — v1 with `any_enforcement` ran but produced `δ_μ[mining] < 0` (see §17 motivation).
4. **Now:** Update `structural_ks_binary.r` to implement the formal/informal split per §17 — Eqs. 2a_formal, 2a_informal, 2b_formal, 2b_informal; add mining to all four; add `any_snsv` to W. Re-run test (N_BOOT = 0) to verify `δ_μ[mining]` sign flips positive.
5. Run bootstrap (N_BOOT = 500) overnight after sign verified.
6. Estimate κ (robustness column, κ free in pseudo-likelihood).
7. Counterfactuals CF1–CF5 with formal-only Δê; recheck CF5 decomposition.
8. CF Validation (OOS Q4 correlation) — check whether `any_snsv` in W improves the Q4 fit.

---

## 14. Open Questions

- Parametric form for `F(·|x)`: log-normal vs. Weibull vs. Gumbel. Report sensitivity.
- Should `x`-bins be quartiles of the IV value, of the IV residual, or of the first-stage prediction? Each gives slightly different cross-bin variation.
- Pool across mining-related contaminants (one `B_it`) or estimate separately for each? With binary outcomes, sparsity may force pooling regardless.
- Bin count `K` for the robustness display and CF Validation split: 4 vs. 8 quartiles. Main estimation is observation-level, so K is no longer load-bearing.
- Should `w_it` in Eq. 5 (regulator side) exclude `v̂_it`? Default: include for consistency with Eq. 4; report both.
- **NEW:** Is κ > 0 and distinguishable from zero? If κ ≈ 0, the formal-only primary spec is validated empirically, not just assumed.
- **NEW:** Does `any_snsv` in W improve the OOS Q4 validation correlation (currently 0.087)? The Q4 anomaly may partly reflect monitoring-intensity composition at high IV values.
- **NEW:** Does `φ_m` in Eq. 2a_formal confirm the h3 2SLS sign (negative) in the probit framework with v̂? This is the structural counterpart to the reduced-form h3 result.
- **NEW:** With formal-only Δê lower for mining CWSs, does `δ_μ[mining]` turn positive (compliance costs higher in mining areas)? This is the diagnostic for whether the enforcement model revision resolves the sign problem.

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

- **Eq. 4 implementation (updated 2026-05-24):** estimate `F(·|x)` by **pseudo-likelihood (Option C)** — a probit on `B_it` with `log Δê(x_it)` as a known offset and `w_it` (including `v̂_it`) parametrizing μ(x) and log σ(x). Uses raw `B_it` rather than the smoothed `p̂(x_it)` from Eq. 3, gaining efficiency and avoiding propagation of Eq. 3 prediction error. Identification leverages full observation-level `x` heterogeneity (sd of Δê = 18.4 days at the panel level vs 7.64 across bin medians).
- **Eq. 3 demoted to diagnostic.** Retained for the §16 Check 3 monotonicity test, the Option B robustness column, and the post-estimation fit check `1 − F̂(Δê|x)` vs `p̂(x)`. Not on the main estimation path.
- **Eq. 5 also moved to observation-level NLS (2026-05-24):** the regulator FOC is a pointwise restriction at every x, so every observation contributes a residual. With N = 6,232 and 2K parameters the system is overidentified by N − 2K, enabling a Hansen J-test for misspecification. The bin-level NLS (K = 4) is retained as a robustness column.
- **Bootstrap SEs:** required. Resample PWSIDs and redo Eqs. 1, 2a_formal, 2a_informal, 2b_formal, 2b_informal, 4 (pseudo-likelihood), 5; report standard errors and percentile intervals.
- **Robustness columns to report alongside Option C:** Option A (PWSID-clustered HAC GMM on residual moments) and Option B (NLS on `1 − p̂` residuals). Eq. 3 is needed to populate Options A and B.
- **Enforcement split (updated 2026-06-01):** `Δê` is now constructed from formal enforcement only (primary) or formal + κ·informal (robustness). See §17 for full motivation and data feasibility assessment. `any_snsv` added to W. Mining enters Eqs. 2a and 2b directly.

### Status

`structural_ks_binary.r` (v1) written and run 2026-06-01. Produced `δ_μ[mining] < 0` due to conflation of formal/informal enforcement in `any_enforcement`. Revision to formal/informal split pending — see §17 and §13 step 4.

---

## 17. Enforcement Model Revision — Formal/Informal Split (2026-06-01)

### Motivation

The first test run of `structural_ks_binary.r` (with state FEs in W) produced `δ_μ[mining] < 0` — the type distribution assigns lower mean compliance cost to mining-exposed CWSs. This is economically backwards: physical mining contamination raises the administrative burden of MR monitoring and reporting, and should push `δ_μ[mining] > 0`. Two diagnostics identified the root cause:

1. **h3_enf_d12.tex** (2SLS, col 6): `any_formal` coefficient on `num_coal_mines_upstream` = **−0.087\*\*\*** — mining CWSs receive significantly *less* formal enforcement, supporting EJ enforcement laxity on the deterrent margin.
2. **h2_snsv_d12.tex** (2SLS): sanitary survey coefficient = **+0.141\*\*\*** — mining CWSs receive significantly *more* monitoring visits.
3. The current `any_enforcement` variable collapses formal (deterrent), informal (low-deterrence), and resolving actions into a single binary. Because informal enforcement dominates (45K informal vs 773 formal actions in sample), the aggregate Δê is insensitive to the EJ laxity in formal enforcement.
4. With Δê approximately equal across mining/non-mining CWSs (formal laxity masked by informal volume), the pseudo-likelihood has no enforcement channel to explain the mining violation gap and sets `δ_μ[mining] < 0` instead.

### Data Availability Assessment (2026-06-01)

**SDWA_VIOLATIONS_ENFORCEMENT.csv** in the downstream 1985–2005 sample (340 PWSIDs, 6,232 obs):

| Type | Raw actions | PWSIDs | PWSID-years | Pr(E=1\|B=1) | Pr(E=1\|B=0) | Feasible in Δê? |
|---|---|---|---|---|---|---|
| Formal | 773 | 111 | 218 | **10.2%** | 2.7% | **Yes** — strong B-gap, 771 RTC obs for 2b |
| Informal | 12,702 | 267 | ~2,100+ | **57.5%** | 14.3% | **Yes** — very thick, strong B-gap |
| Any (current) | 19,870 | 268 | ~2,900 | ~60% | ~17% | Yes — current spec, becomes robustness |

**SDWA_SITE_VISITS.csv** (SNSV, SNSP, L1SS, L2SS, SSVF codes):

| Type | PWSID-years | Pr(visit\|B=1) | Pr(visit\|B=0) | Role |
|---|---|---|---|---|
| Sanitary surveys | 910 | **14.04%** | **14.62%** | **W covariate only** — no B-conditional gap, zero deterrence content |

Sanitary surveys are scheduled inspections independent of violations (gap of 0.58 pp is noise). Including them in Δê would add zero enforcement differential. They belong in W as a monitoring-intensity covariate for F(θ|x).

Formal enforcement dominant type: **SFR (State Consent Decree/Judgement)** = 473 records — the most binding category.

### Revised Model Structure

**New two-point schedule:**

```
Δê(x_it) = Δê_formal(x_it) + κ · Δê_informal(x_it)

ê_formal(B|x)   = Pr̂(E_formal=1|B,x) · Ê[days_to_RTC|E_formal=1,B,x]
ê_informal(B|x) = Pr̂(E_informal=1|B,x) · Ê[days_to_RTC|E_informal=1,B,x]
Δê_formal       = ê_formal(1|x) − ê_formal(0|x)
Δê_informal     = ê_informal(1|x) − ê_informal(0|x)
```

`κ ∈ [0,1]` = relative deterrence weight of informal vs formal enforcement.
**Primary spec:** `κ = 0` (formal only, cleanest interpretation).
**Robustness:** `κ` estimated jointly in pseudo-likelihood as a free parameter (adds one scalar to Eq. 4 log-likelihood).

### Revised Equations 2a and 2b

Mining (`log(1+num_coal_mines_upstream)`) enters **both** enforcement equations directly, so Δê varies with mining exposure — enabling the enforcement laxity channel.

**Eq. 2a_formal:**
```
Pr(E_formal_it = 1 | B_it, x_it, v̂_it) = Φ(φ₀ + φ_B·B_it + φ_m·log(1+m_it) + x_it'·φ_x + φ_v·v̂_it)
```

**Eq. 2a_informal:**
```
Pr(E_informal_it = 1 | B_it, x_it, v̂_it) = Φ(ψ₀ + ψ_B·B_it + ψ_m·log(1+m_it) + x_it'·ψ_x + ψ_v·v̂_it)
```

**Eq. 2b_formal** (on `E_formal = 1` subset):
```
log(days_to_RTC_it + 1) = ξ₀ + ξ_B·B_it + ξ_m·log(1+m_it) + x_it'·ξ_x + u_it
```

**Eq. 2b_informal** (on `E_informal = 1` subset, `E_formal = 0`):
```
log(days_to_RTC_it + 1) = ζ₀ + ζ_B·B_it + ζ_m·log(1+m_it) + x_it'·ζ_x + u_it
```

Expected signs: `φ_m < 0` (EJ laxity — less formal enforcement in mining areas), `ψ_m ≥ 0` (informal enforcement similar or more in mining areas).

### Revised W Matrix (Eqs. 4 and 5)

Add `any_snsv` (sanitary survey indicator, lagged or contemporaneous) as a monitoring-intensity covariate. More monitored CWSs face higher detection risk and may have different compliance cost distributions. Exclusion from Δê is justified by the near-zero B-conditional gap.

```r
W <- model.matrix(
  ~ log(1 + num_coal_mines_upstream) + sulfur_unified +
    num_facilities + log(POPULATION_SERVED_COUNT + 1) +
    factor(OWNER_TYPE_CODE) + factor(PRIMARY_SOURCE_CODE) +
    factor(state) + any_snsv + v_hat,
  data = panel_cc
)
```

### Expected Identification Consequences

With `φ_m < 0` (from Eq. 2a_formal — as h3 already documents causally):
- Δê_formal is **lower** for mining CWSs
- The pseudo-likelihood offset `log(Δê)` is smaller for mining obs
- The pseudo-likelihood can fit high violation rates in mining areas through lower Δê (enforcement laxity), and the residual falls on `δ_μ[mining]`
- **Expected result:** `δ_μ[mining] > 0` (higher compliance costs from physical contamination burden), consistent with economic priors

### Identification of κ (robustness)

In the pseudo-likelihood with composite offset:
```
η_it = (log(Δê_formal + κ·Δê_informal) − w_it'·δ_μ) / exp(w_it'·δ_σ)
```
κ enters the offset nonlinearly. Identification comes from cross-CWS variation in the ratio `Δê_informal / Δê_formal`: CWSs where informal and formal schedules differ most informatively bound κ. With the enforcement subsample showing large heterogeneity in enforcement type composition, κ should be identified. Estimate as `κ = exp(κ_par)` (constrained positive) with starting value `κ_par = log(0.3)`.

### Updated Bootstrap Protocol

Resample PWSIDs, redo Eqs. 1, **2a_formal, 2a_informal, 2b_formal, 2b_informal**, 4, 5. All five enforcement equations must be re-estimated in each bootstrap rep. Add robustness rep with `κ` free (500 reps as before).

### Open Questions Added

- Does `φ_m` in Eq. 2a_formal have the expected negative sign after conditioning on PWSID + year + state FEs? (Already answered in reduced form by h3 2SLS, but needs reconfirmation in the probit framework with v̂.)
- Is κ > 0 and statistically distinguishable from zero? If κ ≈ 0 (formal-only), the simpler primary spec is validated.
- With `any_snsv` in W: does survey monitoring absorb the Q4 OOS validation failure? The Q4 anomaly may partly reflect higher monitoring intensity in high-IV CWSs.

### Implementation Status

- [x] Add formal/informal indicators and `any_snsv` to `structural_ks_binary.r` data loading
- [x] Replace fits 2a/2b with 2a_formal, 2a_informal, 2b_formal, 2b_informal
- [x] Add mining to all four enforcement equations
- [x] Construct composite Δê with κ = 0 (primary) and κ free (robustness)
- [x] Add `any_snsv` to W and W_reg
- [x] Re-run test (N_BOOT = 0) — **sign flip DID NOT resolve** (see §18)
- [ ] Re-run bootstrap (N_BOOT = 500) overnight after sign verified

---

## 18. Test-Run Results — Formal/Informal Split (2026-06-01)

Script ran cleanly (exit 0, N_BOOT=0). Key outputs:

| Check | Result |
|---|---|
| Formal enforcement: 111 PWSIDs, Pr(formal=1)=0.095 | ✓ matches prior count |
| Informal: 267 PWSIDs, Pr(informal=1)=0.223 | ✓ |
| any_snsv: 907 PWSID-years | ✓ loaded |
| φ_m_formal = −0.360 (t=−2.93) | ✓ EJ enforcement laxity confirmed in probit |
| φ_m_informal = −0.294 (t=−3.94) | Both types show laxity (unexpected for informal) |
| ξ_m_formal = −0.485 (t=−2.18) | Shorter days-to-RTC in mining areas when formally enforced |
| cor(mines_upstream, Δê_formal) = −0.683 | ✓ Enforcement differential is strongly lower for mining CWSs |
| Δê_formal: mean=26.7, sd=9.5 days | Much smaller scale than combined (was ~135 days) |
| **δ_μ[mining] = −1.051 — NEGATIVE** | **Sign flip NOT resolved** |
| Hazard tail: max=5×10¹³ >> q99=1929 | Log-normal badly conditioned in right tail; winsorized |

### Root Cause Analysis

The formal-only Δê has `cor(mines, Δê_formal) = −0.683` — so strongly negative that the pseudo-likelihood offset `log(Δê_formal)` already **over-explains** the mining violation gap by itself. Mining CWSs have log(Δê_formal) ≈ 0.683 SDs lower, which pushes Pr(B=1) upward even before μ(x) is fit. The residual that falls on δ_μ[mining] is then **negative** (the model needs to lower the compliance-cost mean to keep Pr(B=1) from exceeding the observed 11%).

The §17 hypothesis was: "lower Δê in mining areas → the pseudo-likelihood uses the offset channel instead of δ_μ." That part is correct, but the offset channel over-corrects: `Δê_formal` is so small (26.7 days mean vs 137 for informal) that even small mining-related reductions in Δê become large in log-space and dominate.

### Candidate Explanations and Next Diagnostics

1. **Scale mismatch**: Formal-only Δê (26.7 days) is structurally too small a deterrent to explain 11% violation rates. The log-normal with offset log(26.7) ≈ 3.28 and empirical mean violation rate 11% implies μ̄ ≈ 3.28 − qnorm(0.89) ≈ 3.28 − 1.23 = 2.05 — but mining has much lower Δê, so the model compensates with lower μ.

2. **Both φ_m and ξ_m are negative for formal**: The product `Pr(E_formal|B=1,x) × E[days|B=1,x]` falls faster with mining than `Pr(E_formal|B=0,x) × E[days|B=0,x]`, compressing Δê_formal in mining areas. This compression drives most of the offset channel.

3. **Log-normal misspecification**: Hazard tail explosion (`max/q99 > 25,000`) suggests the log-normal is poorly specified at the tails. Alternative: use κ > 0 (add informal to Δê to increase scale and reduce the negative correlation).

### Next Steps (Priority Order)

1. **Try κ = 1 (formal + informal combined)** — `Δê = Δê_formal + Δê_informal` (mean ~163 days, with smaller relative gap). This reduces the dominance of the enforcement laxity channel and may allow δ_μ[mining] to be positive. Single-line change: `kappa <- 1`.

2. **Try κ free (estimated in pseudo-likelihood)** — estimate κ jointly with δ_μ, δ_σ as planned in the robustness spec. κ̂ should tell us how much informal weight is needed to resolve the sign.

3. **Check raw bin means of Δê by mining quartile** — verify whether the formal-only schedule actually has structural content at the observation level that identification can use.

4. **Consider composite schedule without separating by RTC duration** — if ξ_m estimates are noisy (217 obs in formal_e1), the 2b step may be amplifying the laxity signal. Try Δê = Pr̂(E_formal|B=1) − Pr̂(E_formal|B=0) only (drop the RTC duration step).

---

## 19. κ Profile Test and Decision to Abandon — 2026-06-02

### What was tried

`structural_kappa_profile.r` was run with:
- `factor(state)` added to all four enforcement equations (Eqs. 2a_formal, 2a_informal, 2b_formal, 2b_informal) — state regulatory heterogeneity placed in Δê where it belongs structurally
- `factor(state)` removed from W — reduces K from ~39 to 17 columns (~20 events per parameter, up from ~9)
- κ grid: {0, 0.1, 0.2, 0.3, 0.5, 0.8, 1.0}

### Results

| κ | log-lik | δ_μ[mining] | converged |
|---|---------|-------------|-----------|
| 0.0 | −1999.2 | +1.374 | No (iter limit) |
| 0.1 | −1989.8 | −0.690 | No (iter limit) |
| 0.2 | −1992.8 | −0.525 | Yes |
| 0.3 | −1995.8 | −0.019 | Yes |
| 0.5 | −2002.9 | −0.020 | No (iter limit) |
| 0.8 | −1998.3 | −0.306 | Yes |
| 1.0 | −1996.2 | +1373 | No (diverged) |

Sign-flip interpolated at κ ≈ 0.067. δ_μ[mining] < 0 for all converged points in κ ∈ [0.1, 0.8].

### Why δ_μ[mining] < 0 is persistent

The enforcement schedule Δê has `cor(mining, Δê_formal) = −0.137` at the panel level. The enforcement equations in Eqs. 2a/2b absorb the state-level component of this laxity; the within-state component remains. Mining appears in both W (compliance cost μ) and the enforcement equations (Δê). The model splits mining's effect between the two channels. With enforcement laxity dominating — mining areas face weaker enforcement, pushing up B=1 through lower Δê — the residual effect on μ is negative. The enforcement channel more than accounts for the high violation rates in mining areas, leaving compliance costs structurally *lower* in mining areas once enforcement is controlled for.

### Modelling options considered and rejected

Three options were considered to recover δ_μ[mining] > 0:

1. **Drop `log(mines)` from 2a/2b enforcement equations** — enforces an exclusion restriction that mining does not affect enforcement intensity. Not defensible given the h3 2SLS result (formal enforcement −0.087*** on upstream mines).

2. **Replace `log(mines)` in W with the instrument `post95 × sulfur_unified`** — changes δ_μ from "effect of mining on compliance cost" to "effect of ARP-driven mining decline on compliance cost." Conflates the first stage with the structural object of interest; loses the quantity-of-mining interpretation.

3. **Drop `log(mines)` from W entirely, rely only on v_hat** — imposes δ_μ[mining] = 0 by assumption. Turns the model into a pure enforcement-heterogeneity model (regulatory capture story), abandoning the compliance cost channel.

None of these options recover the compliance cost interpretation without an unjustifiable restriction. The negative sign is not a numerical artifact — it reflects the structural tension that enforcement laxity in mining areas fully explains the high MR violation rate, leaving no role for elevated compliance costs.

### Decision

**The structural model is abandoned.** The result δ_μ[mining] < 0 is economically implausible as a compliance cost parameter (mining raises raw water contamination burden; compliance should be more expensive, not less). There is no modelling fix that resolves this without imposing an exclusion restriction that contradicts established reduced-form evidence or changing the interpretation of the structural object so fundamentally that the original research question is no longer answered.

The enforcement laxity finding (mining areas receive less formal enforcement) is robust and well-identified from the reduced form. The next step is to explore this enforcement channel directly with reduced-form and descriptive tools outside the structural framework — see the enforcement exploration plan (2026-06-02 session log).

---

## 20. Core Diagnosis — The Observed-vs-Latent Asymmetry (2026-06-02)

The biggest issue right now is an asymmetry between the two channels that drive MR
violations:

- **Enforcement actions are recorded in the SDWA data — you can regress on them directly.**
  Mining → less formal enforcement is IV-identified in `h3_inf_formal_d12.tex` (2SLS −0.0565***, F = 27.84).
- **Compliance cost θ is a latent primitive — it is never in any dataset.** Nothing observes
  the cost a CWS bears to comply on a given contaminant.

So "I can measure the enforcement channel but not the cost channel" is partly just "one is
observed and one isn't." The structural model was the attempt to back out the latent θ, and
it failed to identify it — **not because θ(m) is flat, but because mining moves enforcement
(λ) and compliance cost (θ) together with no wedge between them.** Both enter the single
violation index η = (log Δê − μ)/σ through the same regressor m, so the data pin down only
the total ∂η/∂m, not the split. With the enforcement schedule estimated externally and
strongly negative in m, the cost slope δ_μ[mining] is left as a residual and turns negative.

**Implication for testing Prop 2 (mining → higher compliance cost).** Because θ is latent
and not separable inside this model, the cost channel must be tested *outside* the structural
framework, by measuring the cost-driver directly rather than backing it out:
- The first link, mining → more raw water contamination, **is now confirmed in the 6-year
  review data.** This establishes the contamination burden that Prop 2 posits as the source
  of higher compliance cost, without relying on the latent θ.
- Remaining direct tests of θ(m): contaminant-specificity of the MR response (AMD-linked vs
  non-mining placebos — enforcement laxity is contaminant-agnostic, contamination cost is
  contaminant-specific), and direct expenditure / treatment-technology proxies where data
  permit.
