# Regulator Reaction Function — Route 3, Working Supply-Side Approach

**Date drafted:** 2026-05-25
**Purpose:** Self-contained reference for the structural model that pairs the MVP CWS logit with a reduced-form regulator reaction function and rational CWS expectations. This is the **working supply-side approach** — it supersedes the FOC document for this project.
**Companion documents:**
- `.claude/logs/2026-05-25-mvp-cws-logit-explainer.md` (MVP demand side — Route 3 modifies how CWS regressors are constructed)
- `.claude/logs/2026-05-25-regulator-supply-side-foc.md` (FOC approach — superseded, kept for reference)

**Status:** Route 3 is the recommended approach. The discrete regulator-as-optimizer model collapses in a static setting (regulator picks a = 0 always because per-period action does not affect this period's j). The FOC version requires interior solutions and IVs for three regulator actions, both implausible. Treating the regulator's behavior as a reduced-form reaction function while keeping the CWS as a rational-expectations optimizer is the simplest specification that (i) gives the right deterrence microfoundation, (ii) needs only one IV, (iii) supports the three target counterfactuals.

---

## 1. What this model is and isn't

**Is:**
- A **structural model of the CWS** with rational expectations over the regulator's response.
- A **reduced-form description of regulator behavior** in the form of an empirical reaction function P̂r(a | j, s).
- **Partial equilibrium with rational CWS expectations** — the CWS optimizes; the regulator is a behavioral rule.

**Is not:**
- A general equilibrium model in the strict sense. The regulator does not optimize.
- A model that identifies the social cost h of an MR violation or the regulator's per-action costs β_k.
- A welfare-counterfactual-capable model without external calibration of h.

**Sales pitch in paper writing:** "We estimate CWS compliance behavior as a rational-expectations response to an empirically-estimated regulatory reaction function." Honest about what is and isn't structural.

---

## 2. Setup and timing

### Choice sets
- **CWS** picks j ∈ {MR, comply} in each year
- **Regulator** picks action profile a ∈ A in each year, where A = {0,1}³ enumerates (visit, formal action, public notification)

### Timing within a period
1. CWS observes its state s_ct (last year's enforcement, cost_save, characteristics)
2. CWS picks j_ct based on rational expectations over the regulator's response
3. Regulator observes j_ct and s_ct, picks a_ct according to its reaction function
4. Costs and outcomes realize

### State variable s_ct
Captures everything the CWS uses to form expectations about the regulator. Candidates for inclusion:
- Lagged enforcement intensity (was this CWS hit hard last year?)
- cost_save quartile or continuous value
- CWS size (POPULATION_SERVED_COUNT bucket)
- ownership type
- state or EPA region (for cross-state enforcement style)

Discretize so that each (j, s) cell has enough observations to tabulate P̂r(a | j, s) without sparsity. A reasonable starting point: 4 cells × 2 j-values × |A|=8 = 64 cells. With 6,232 PWSID-year obs in the downstream sample, that gives ~100 obs per cell, marginal for the rare actions but workable.

---

## 3. CWS optimization with rational expectations

### Utility from each choice
The CWS at state s anticipates that picking j will trigger the regulator's response according to P̂r(a | j, s). The CWS's expected utility from j:
```
EU(MR | s)     = E_a[α₁·v + α₂·f + α₃·n | j=MR, s] + α₄·cost_save + ε(MR)
              = α'·E[a | MR, s] + α₄·cost_save + ε(MR)

EU(comply | s) = E_a[α₁·v + α₂·f + α₃·n | j=comply, s] + ε(comply)
              = α'·E[a | comply, s] + ε(comply)
```
Note that α₄·cost_save enters only the MR utility — the savings only materialize if the CWS skips the test.

### The deterrent
Subtract:
```
Δu(s) = α'·Δa(s) + α₄·cost_save(s) + [ε(MR) − ε(comply)]

where Δa(s) = E[a | MR, s] − E[a | comply, s] is the *differential* enforcement
the CWS expects to trigger by violating rather than complying.
```

If the regulator enforces equally regardless of j, then Δa = 0 and the CWS faces no deterrent. The level of enforcement does not deter; only the differential does. This is the correct microfoundation and is the central insight Route 3 brings to the MVP.

### Choice probability (binary logit)
```
P(MR | s) = exp(α₁·Δv(s) + α₂·Δf(s) + α₃·Δn(s) + α₄·cost_save(s))
          / [1 + exp(α₁·Δv(s) + α₂·Δf(s) + α₃·Δn(s) + α₄·cost_save(s))]
```

---

## 4. Regulator's reaction function (reduced form)

Treat P̂r(a | j, s) as an empirical conditional probability — tabulated, not modeled.

### Construction
```
For each (j, s) cell:
  For each a ∈ A:
    P̂r(a | j, s) = #{obs in cell with action a} / #{obs in cell}
```

That's it. No optimization, no structural parameters on the regulator side. The reaction function is a 3-way contingency table over (a, j, s).

### What this assumes about the regulator
- **Stationarity:** the reaction function is constant over the sample period within (j, s) cells. Test by splitting the sample (pre-1995 vs. post-1995) and comparing.
- **Behavioral rule:** the regulator follows the same rule across CWSs in the same state. Heterogeneity not in s is treated as exogenous noise.
- **Knowability:** the CWS knows P̂r(a | j, s). Defensible for SDWA where enforcement policy is published EPA guidance.

### What it does *not* assume
- That the regulator is optimizing
- That P̂r(a | j, s) is constant under counterfactual policies — it is the baseline, and counterfactuals perturb it explicitly

---

## 5. Equilibrium concept

A **rational-expectations partial equilibrium** is a tuple (P(MR | s), P̂r(a | j, s)) such that:
1. **CWS best response:** P(MR | s) is the binary-logit choice probability with Δa(s) constructed from P̂r(a | j, s)
2. **Regulator's reaction function** is taken as observed; not a best response

This is well-defined and unique given P̂r. No fixed-point computation in the baseline — the reaction function pins Δa, which pins P(MR | s). One pass.

Counterfactual equilibrium is similarly one-pass: the policy perturbs P̂r → new Δa → new P(MR | s).

---

## 6. Estimation

### Step 0 — Decide on s_ct discretization
Choose state bins to balance richness vs. cell sparsity. Inspect cell counts before committing.

### Step 1 — Tabulate the reaction function
```r
# pseudocode
P_hat_a_given_j_s <- dt[, .N, by = .(j, s, a)][, prob := N / sum(N), by = .(j, s)]
```
Inspect: are there cells with < 30 observations? Coarsen s if so.

### Step 2 — Construct Δa(s) for each state
```r
E_a_MR     <- dt[j == "MR",     mean(a), by = s]
E_a_comply <- dt[j == "comply", mean(a), by = s]
Delta_a    <- merge(E_a_MR, E_a_comply, by = "s")[, .(Δv, Δf, Δn)]
```
Three differential expectations per state: Δv(s), Δf(s), Δn(s).

### Step 3 — First stage for cost_save
The only remaining endogeneity is cost_save (mining-driven). Control function:
```r
fs_cost_save <- feols(cost_save ~ post95:sulfur_unified | PWSID + year + state, dt)
dt[, v_cost_save := resid(fs_cost_save)]
```

### Step 4 — CWS binary logit MLE
```r
# Merge Δa(s_ct) onto the CWS panel
dt <- merge(dt, Delta_a, by = "s")

fit <- feglm(MR ~ Δv + Δf + Δn + cost_save + v_cost_save |
                  PWSID + year + state,
             data = dt, family = binomial("logit"),
             cluster = ~ PWSID)
```
Coefficients α₁, α₂, α₃ measure how much expected differential enforcement deters MR. α₄ measures the cost-savings pull toward MR.

### Step 5 — Inference
Block bootstrap by PWSID. Two layers: (i) resample, (ii) re-tabulate P̂r and refit logit. Δa is a generated regressor — naïve SEs understate.

---

## 7. Counterfactuals

All counterfactuals act on the reaction function. Construct the perturbed P̂r', compute new Δa', plug into the CWS logit for new P(MR | s).

### CF1 — Regulator visits increased
Shift Pr(v=1 | j, s) upward by some amount δ for both j ∈ {MR, comply}:
```r
P_hat_cf1 <- copy(P_hat); P_hat_cf1[a includes v=1, prob := pmin(1, prob + delta)]
# renormalize within (j, s)
```
Recompute E[v | j, s] and Δv'(s). Δv' may be larger, smaller, or unchanged depending on whether the shift differs across j. If uniform, Δv' = Δv (no change in deterrent!), so the counterfactual reduces to "regulator inspects more but deterrence unchanged." That is the right answer if extra inspections are spread evenly.

**Counterfactual variant** to get a genuine deterrence shift: shift Pr(v=1 | MR, s) up by δ_MR and Pr(v=1 | comply, s) by δ_comply < δ_MR. The reaction function tightens around violations. Δv' > Δv and deterrence rises.

### CF2 — Public notification always required
```
P̂r'(a | j, s) = P̂r(a | j, s) restricted to a with n=1, renormalized
```
After the policy, E[n | MR, s] = E[n | comply, s] = 1, so Δn' = 0. Notification's deterrent value disappears (it hits both types equally). The CWS no longer gets deterred by notification — but the CWS's utility loses α₃·1 in both branches, which cancels.

The net effect comes from the regulator's reallocation: with notification fixed, how does Pr(v | j, s) and Pr(f | j, s) change? In Route 3 you cannot derive this — you'd need a regulator optimizer. The honest answer is to fix the marginal frequencies of v and f at observed levels and let Δv, Δf carry through. Report the result as "if notification became universal *and* the regulator's response on other tools stayed the same."

This is a real limitation of Route 3. To say more, you need Route 2 or Route 1.

### CF3 — No upstream mining
```
cost_save'_ct = fitted cost_save at num_coal_mines_upstream = 0
```
Δa(s) is unaffected (assuming s doesn't include mining-related variables). The CWS logit reads off the new P(MR | s, cost_save'). This is the cleanest of the three counterfactuals because the channel runs entirely through cost_save.

**Variant:** if s includes mining-related state (likely, since past enforcement may correlate with mining intensity), recompute P̂r at the no-mining s'. This shifts the reaction function as well as cost_save.

### Standard errors
Bootstrap by PWSID for all counterfactuals. Report 95% percentile CIs.

---

## 8. Identification — what's pinned and what isn't

| Object | Identified? | Source |
|---|---|---|
| α₁, α₂, α₃ (CWS deterrence elasticities) | Yes | Variation in Δa(s) across states + variation in MR across CWSs |
| α₄ (cost-savings pull) | Yes (with IV) | ARP × sulfur first stage |
| P̂r(a | j, s) | Yes (sample average) | Direct tabulation |
| Δa(s) | Yes (derived) | From P̂r(a | j, s) |
| β_k (regulator's per-action costs) | **No** | Regulator not modeled as optimizer |
| h (social cost of MR) | **No** | Not in any estimated equation |
| Welfare | **No, without external calibration** | Needs h and β_k from outside |

### The Δa = 0 identification problem
If for some action k the regulator's response is constant across j within state s (e.g., the regulator always sends notifications regardless), Δk(s) = 0 in that state and α_k is not identified from that state's variation. Need cross-state variation in Δa to identify α — i.e., need *some* states where the regulator differentially responds to MR.

If across all states Δk(s) ≈ 0 for some k, that α_k is not identified at all. This is a real risk — public notifications in particular may be near-mandatory in some periods and absent in others without much j-conditional variation. Inspect Δa(s) before estimating; drop or merge actions if they have no variation.

---

## 9. Concrete changes from MVP

If you have an MVP implementation and want to upgrade to Route 3, here is the diff:

**Add (before the CWS logit):**
- Define s_ct discretization (a new variable on the panel)
- Tabulate P̂r(a | j, s) from the data
- Construct Δv(s), Δf(s), Δn(s) and merge onto the panel

**Modify (the CWS logit):**
- Replace regressors (visits, formal, notif) with (Δv(s_ct), Δf(s_ct), Δn(s_ct))
- Keep cost_save as a regressor; keep its control-function residual
- **Drop** the control-function residuals for visits/formal/notif (no longer needed because those variables no longer enter the logit)

**Modify (counterfactuals):**
- Instead of plugging new (v, f, n) values per observation, perturb P̂r(a | j, s) (the reaction function) and recompute Δa(s)
- For mandatory-notification, set the relevant subset of P̂r' to satisfy n=1; renormalize
- For more inspections, shift the reaction function with explicit assumption about how the shift falls across j

**Drop:**
- IV requirement for visits, formal, notif — Route 3 doesn't need them
- The Petrin-Train residuals for those three variables

**Keep:**
- IV / first stage for cost_save (ARP × sulfur)
- PWSID + year + state fixed effects
- Block bootstrap by PWSID

---

## 10. R code sketch

```r
library(arrow); library(fixest); library(data.table)

dt <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet") |> as.data.table()
dt <- dt[minehuc_downstream_of_mine == 1 & minehuc_mine == 0 &
         year >= 1985 & year <= 2005 & PWSID != "WV3303401"]

# Step 0: define state variable s
dt[, cs_q := cut(cost_save, breaks = quantile(cost_save, 0:4/4, na.rm=TRUE),
                 include.lowest = TRUE, labels = 1:4)]
dt[, lag_enf := shift(visits + formal + notif > 0, fill = 0), by = PWSID]
dt[, s := paste0(cs_q, "_", as.integer(lag_enf))]

# Step 1: reaction function (we use marginal expectations, not full joint)
react_MR     <- dt[MR == 1, .(Ev_MR = mean(visits), Ef_MR = mean(formal),
                              En_MR = mean(notif)), by = s]
react_comply <- dt[MR == 0, .(Ev_co = mean(visits), Ef_co = mean(formal),
                              En_co = mean(notif)), by = s]

# Step 2: Δa(s)
delta_a <- merge(react_MR, react_comply, by = "s")
delta_a[, `:=`(Dv = Ev_MR - Ev_co,
               Df = Ef_MR - Ef_co,
               Dn = En_MR - En_co)]

dt <- merge(dt, delta_a[, .(s, Dv, Df, Dn)], by = "s")

# Step 3: control function for cost_save
fs <- feols(cost_save ~ post95:sulfur_unified | PWSID + year + state, dt)
dt[, v_cost_save := resid(fs)]

# Step 4: CWS logit on differential enforcement + cost_save
fit <- feglm(MR ~ Dv + Df + Dn + cost_save + v_cost_save |
                  PWSID + year + state,
             data = dt, family = binomial("logit"),
             cluster = ~ PWSID)
summary(fit)

# Step 5: counterfactual CF3 (no mining)
fs_nom <- predict(fs, newdata = dt[, .(post95, sulfur_unified = 0,
                                       PWSID, year, state)])
dt[, cost_save_nom := fs_nom]
dt[, P_baseline := predict(fit, dt, type = "response")]

dt_cf3 <- copy(dt); dt_cf3[, cost_save := cost_save_nom]
dt_cf3[, P_cf3 := predict(fit, dt_cf3, type = "response")]

dt_cf3[, .(baseline = mean(P_baseline),
           cf       = mean(P_cf3),
           Δ        = mean(P_cf3 - P_baseline))]
```

---

## 11. Open design choices to settle before coding

1. **State variable s.** What goes in? Lagged enforcement, cost_save quartile, size, ownership. Inspect cell counts before committing.
2. **Marginal vs joint reaction function.** Above uses marginal E[v | j, s] etc. The joint P̂r(a | j, s) is more general but requires more data per cell. For three binary actions × 2 j × 4 s = 64 cells, joint is feasible.
3. **How to perturb P̂r for CF1.** A uniform shift in Pr(v=1) doesn't change Δv. Realistic policy variants need to assume an allocation rule for the extra inspections — flag this explicitly in writing.
4. **Stationarity of P̂r.** Test by splitting sample. If reaction function shifted at 1996 amendments, estimate two reaction functions.
5. **Action enumeration.** Are v, f, n binary or counts? Visits especially might be {0, 1, 2+}. Larger A = sparser cells but richer model.

---

## 12. Empirical cell-count feasibility (2026-05-25)

Cell-count diagnosis on the downstream sample (N=6,232 PWSID-year, 340 PWSIDs) shows
**10-25 cells is the empirically feasible range** for s before MR-side sparsity bites:

| s definition | # cells | Min cell N | Min MR-side N | Cells <30 MR obs |
|---|---|---|---|---|
| prod_q × lag_MR | 10 | 90 | 45 | 0 |
| prod_q × sulf_q | 25 | 19 | 0 | 11 |
| prod_q × lag_MR × size | 30 | 13 | 4 | 19 |
| prod_q × sulf_q × lag_MR | 49 | 2 | 0 | 38 |

Within-PWSID variation in s is healthy when lag_enf is in the mix: 90% of PWSIDs
change cells over time, so PWSID FE does not wipe out Δa variation.

### To-do before fitting the logit

1. Build `visits`, `formal`, `notif`, `cost_save` from SDWA enforcement files.
2. Pick the 10-cell `prod_q × lag_MR` baseline.
3. Inspect Δa(s) before fitting the logit — if you see meaningful spread in all
   three Δ's and they are not collinear, Route 3 is alive.

---

## 13. Links

- MVP companion: `.claude/logs/2026-05-25-mvp-cws-logit-explainer.md`
- FOC version (superseded): `.claude/logs/2026-05-25-regulator-supply-side-foc.md`
- Template: `.claude/skills/counterfactual_structural_modelling_basics.md`
- Prior K&S attempt this avoids: `.claude/logs/2026-05-06-structural-model-analysis.md`
- N-and-variation diagnosis from K&S route: `.claude/logs/2026-05-22-structural-regression-N-variation.md`
- Originating chat session: 2026-05-25
