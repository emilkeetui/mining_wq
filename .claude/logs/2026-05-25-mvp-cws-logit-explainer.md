# Minimum-Viable Structural Model: CWS Binary Logit

**Date drafted:** 2026-05-25
**Purpose:** Self-contained reference for the simplest structural model that delivers the three target counterfactuals (more inspections, mandatory public notification, no upstream mining). Follows the template in `.claude/skills/counterfactual_structural_modelling_basics.md`, simplified to the demand side only.
**Companion document:** `.claude/logs/2026-05-25-regulator-supply-side-foc.md` (full equilibrium extension, deferred).

---

## 1. What this model does and doesn't do

**Does:**
- Recover CWS preferences over compliance vs. MR violation as a function of regulator actions and the cost savings from skipping monitoring.
- Deliver "plug-and-chug" counterfactual predictions of the form "if x changed to x', P(MR) would change by Δ".
- Provide a structural interpretation of the reduced-form 2SLS result — α₄ on `cost_save` is the channel through which mining moves violations.

**Doesn't:**
- Model the regulator as an optimizing agent. Regulator actions are held fixed at observed values in counterfactuals.
- Identify the social cost h of an MR violation.
- Re-equilibrate enforcement after a policy change.

This is the analogue of estimating only the "consumer" side of a BLP model and asking "what happens to demand if x changes?" without re-solving firm pricing.

---

## 2. Model

### CWS choice set
Each CWS c in year t picks one of two alternatives:
- **MR** — commit a monitoring-and-reporting violation
- **comply** — report on schedule (outside option)

### Utility
```
u_ct(MR)     = α₁·visits_ct + α₂·formal_ct + α₃·notif_ct + α₄·cost_save_ct + ε_ct(MR)
u_ct(comply) = 0 + ε_ct(comply)
```
ε iid Type-I extreme value. Compliance utility is normalized to zero (standard logit identification).

### Choice probability
```
P(MR | x_ct) = exp(Δu_ct) / [1 + exp(Δu_ct)]
Δu_ct        = α₁·visits + α₂·formal + α₃·notif + α₄·cost_save
```

### Variables
| Variable | Meaning | Source |
|---|---|---|
| `visits_ct` | regulator inspections / sanitary surveys in year t | SDWA enforcement records |
| `formal_ct` | formal enforcement actions (orders, penalties) | SDWA enforcement |
| `notif_ct` | public notifications issued | SDWA public notice file |
| `cost_save_ct` | cost savings to CWS from skipping monitoring; depends on mining-driven contamination | constructed |
| `MR_ct` (outcome) | indicator: any MR violation in year t | SDWA violations |

`cost_save` is the channel through which mining matters: more upstream mining → more contamination → higher per-test monitoring cost → larger savings from skipping → higher P(MR).

### Expected signs
- α₁ < 0 — more visits raise the probability of detection, deterring MR
- α₂ < 0 — formal actions are costly, deter MR
- α₃ < 0 — public notification is reputationally costly, deters MR
- α₄ > 0 — larger cost savings make MR more attractive

---

## 3. Estimation

### Step 1 — First stage (control function for endogeneity)

The regulator chooses visits, formal, notif partly in response to unobserved CWS characteristics that also affect P(MR). `cost_save` depends on mining, which is endogenous to local water quality demand for similar reasons. Petrin–Train control function:

For each endogenous regressor k ∈ {visits, formal, notif, cost_save}, run a first-stage regression on instruments + exogenous controls + fixed effects, collect residual v̂_k_ct.

Candidate instruments:
- **cost_save:** ARP × `sulfur_unified` (the existing project IV)
- **visits, formal, notif:** harder. Candidates — state-level enforcement budgets, regional EPA staffing changes, neighboring-state enforcement spillovers, lagged values (under a strict exogeneity assumption)

If defensible IVs cannot be found for visits/formal/notif, the fallback is to assume those regulator actions are exogenous conditional on rich PWSID + year + state fixed effects and stress-test with sensitivity analysis. This is a real weakness; flag it.

### Step 2 — Augmented logit MLE

Maximize the log-likelihood:
```
ℓ(α, λ) = Σ_ct [MR_ct · log P(MR | x_ct, v̂_ct) + (1 − MR_ct) · log P(comply | x_ct, v̂_ct)]
```
with augmented utility:
```
Δu_ct = α₁·visits + α₂·formal + α₃·notif + α₄·cost_save
        + λ₁·v̂_visits + λ₂·v̂_formal + λ₃·v̂_notif + λ₄·v̂_cost_save
```
The residuals absorb the endogenous component of each regressor. Test λ_k = 0 to assess exogeneity of regressor k.

### Step 3 — Inference

Bootstrap clustered at PWSID. Naïve SEs understate uncertainty because v̂ is a generated regressor and there is panel structure.

---

## 4. Counterfactuals

For each counterfactual, replace x_ct with x'_ct, compute P(MR | x'_ct, v̂_ct), aggregate.

### CF1 — Regulator visits increased by X%
```
x'_ct = (visits_ct · (1+X), formal_ct, notif_ct, cost_save_ct)
ΔP(MR)_ct = P(MR | x'_ct) − P(MR | x_ct)
Total effect = mean(ΔP)  or  POPULATION_SERVED-weighted mean
```

### CF2 — Public notification always required
```
x'_ct = (visits_ct, formal_ct, 1, cost_save_ct)
ΔP(MR)_ct = P(MR | x'_ct) − P(MR | x_ct)
```

### CF3 — No upstream mining
```
cost_save'_ct = fitted cost_save at num_coal_mines_upstream = 0
                (from first-stage regression with mining inputs zeroed)
x'_ct = (visits_ct, formal_ct, notif_ct, cost_save'_ct)
ΔP(MR)_ct = P(MR | x'_ct) − P(MR | x_ct)
```

### Standard errors
Block-bootstrap by PWSID: resample, re-run first stage and logit, recompute Δ. Report 95% percentile CIs.

---

## 5. Partial-equilibrium interpretation

The counterfactuals report the **direct, first-order effect on CWS compliance behavior, holding regulator enforcement fixed at observed values.**

| CF | Held fixed | What's missed |
|---|---|---|
| Visits ↑X% | Formal action, notif | Regulator substituting away from formal/notif; targeting visits at high-risk CWSs rather than uniform |
| Notif always | Visits, formal | Regulator reducing visits/formal where notif now does the work |
| No mining | All regulator actions | Regulator reducing enforcement at newly-clean CWSs |

### Defensible framings for the paper

- **Mandate framing.** If the policy is a binding rule the regulator cannot circumvent — Congress mandates notification; Congress appropriates extra inspection budget uniformly distributed — then partial equilibrium *is* the policy experiment.
- **Lower-bound framing.** If the regulator would reallocate to reinforce the policy (more visits where MR is most damaging), the partial-equilibrium answer is a conservative lower bound on the full effect.
- **First-order Lucas-critique caveat.** State explicitly that the prediction is a direct partial-equilibrium response; a full equilibrium answer would require modeling the regulator's reallocation. Defer to companion doc.

---

## 6. What this version delivers for the paper

| Result | Source |
|---|---|
| α coefficients describe how each regulator action and mining shock shift CWS compliance | Step 2 MLE |
| "If mandatory notification, MR violations would fall by X%" | CF2 |
| "If mining had not occurred, MR violations would have been Y% lower" | CF3 |
| "Doubling inspections would reduce MR by Z%" | CF1 |
| Structural reading of the reduced-form 2SLS effect: α̂₄ × ARP-driven change in cost_save | Combine Step 2 with reduced form |

This is enough for AEJ:Applied or JEEM if the IV story is clean and the partial-equilibrium framing is honest. Not enough for JPE-level structural.

---

## 7. Things to decide before coding

1. **Functional form of cost_save.** Observed directly, constructed from monitoring requirements × per-test cost, or proxied? Write a clear definition before estimation.
2. **What counts as a "visit"?** Sanitary surveys only, or all SDWA site visits? Per-year count or 0/1?
3. **Formal action.** Indicator or count? Aggregate or split by severity?
4. **Notification.** Public notice as observed in SDWA, or specific to mining-related contaminants?
5. **Sample.** Same downstream-only sample as the 2SLS (N ≈ 6,232 PWSID×year)? Or full sample to maximize variation in regulator actions?
6. **IV strategy for visits/formal/notif.** Hardest practical question. If no defensible IVs, fall back to FE-only and stress-test.

---

## 8. R code sketch

```r
library(arrow); library(fixest); library(data.table)

dt <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet") |> as.data.table()
dt <- dt[minehuc_downstream_of_mine == 1 & minehuc_mine == 0 &
         year >= 1985 & year <= 2005 & PWSID != "WV3303401"]

# Step 1: control function residuals
fs_cost_save <- feols(cost_save ~ post95:sulfur_unified | PWSID + year + state, dt)
dt[, v_cost_save := resid(fs_cost_save)]

# fs_visits, fs_formal, fs_notif similarly — IVs TBD
# fallback: skip CF for these and assume conditional exogeneity given FE

# Step 2: binary logit with control function residuals
fit <- feglm(MR ~ visits + formal + notif + cost_save +
                  v_cost_save |
                  PWSID + year + state,
             data = dt, family = binomial("logit"),
             cluster = ~ PWSID)

# Step 3: counterfactual prediction
dt[, P_baseline := predict(fit, dt, type = "response")]

dt_cf <- copy(dt); dt_cf[, notif := 1]
dt_cf[, P_cf_notif := predict(fit, dt_cf, type = "response")]

cf2 <- dt_cf[, .(baseline = mean(P_baseline),
                  cf       = mean(P_cf_notif),
                  Δ        = mean(P_cf_notif - P_baseline))]
print(cf2)
```

---

## 9. Links

- Template: `.claude/skills/counterfactual_structural_modelling_basics.md`
- General-equilibrium extension (regulator FOC): `.claude/logs/2026-05-25-regulator-supply-side-foc.md`
- Prior K&S attempt that this avoids: `.claude/logs/2026-05-06-structural-model-analysis.md`
- N and variation analysis from the prior K&S route: `.claude/logs/2026-05-22-structural-regression-N-variation.md`
- Originating chat session: 2026-05-25 (Q: can the basics-skill template substitute for the K&S model?)
