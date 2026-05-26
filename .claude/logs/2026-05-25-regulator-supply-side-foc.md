# Regulator Supply Side: FOCs, Cross-Equation Restriction, and Identification

**Date drafted:** 2026-05-25
**Purpose:** Self-contained working-out of the regulator's optimization problem to support a future general-equilibrium extension of the minimum-viable structural model.
**Companion document:** `.claude/logs/2026-05-25-mvp-cws-logit-explainer.md` (the CWS-only demand-side version).

**Verdict (top of mind):** workable in principle. Becomes estimable conditional on four things — (i) defensible IVs for the three regulator actions, (ii) cross-equation restriction holds (or convex-cost extension works), (iii) commitment to a normalization (β₁ = 1), (iv) interior-solution assumption holds at enough observations to justify FOC-based estimation. If any of those fails badly, the supply side collapses to a discrete-choice regulator model — feasible but a separate undertaking.

---

**⚠ SUPERSEDED (2026-05-25).** This FOC approach is no longer the working supply-side model. Three problems pushed us off it: (1) regulator actions are discrete, not continuous, so FOCs are the wrong tool; (2) the discrete one-shot version collapses (regulator picks zero enforcement because per-period action does not affect this period's already-realized j); (3) the IV requirement for three regulator actions is intractable. The working approach is now the reduced-form regulator reaction function in `2026-05-25-regulator-reaction-function-route3.md`, paired with rational CWS expectations. Keep this document as a benchmark / reference for what a regulator-optimizer model would have looked like.

---

---

## 1. Setup

### CWS demand (recap)
```
u_ct(MR)     = α₁·visits + α₂·formal + α₃·notif + α₄·cost_save + ε_ct(MR)
u_ct(comply) = 0 + ε_ct(comply)
P(MR | x_ct) = exp(Δu_ct) / [1 + exp(Δu_ct)]
```

### Regulator's realized cost
```
C_ct = β₁·h · 1{MR_ct} + β₂·visits_ct + β₃·formal_ct + β₄·notif_ct + β₅·Δu_ct · 1{MR_ct}
```
- β₁·h = (weight on social cost) × (per-violation social cost)
- β₂, β₃, β₄ = direct regulator costs of each enforcement action
- β₅·Δu = surplus the CWS extracts from MR that the regulator internalizes (β₅ may be 0 if regulator only cares about social harm)

The regulator chooses (visits, formal, notif) before observing the CWS's ε_ct(MR) − ε_ct(comply), so the 1{MR} indicator is random. Taking expectation over ε:
```
E[C_ct] = (β₁·h + β₅·Δu_ct) · P(MR | x_ct) + β₂·visits + β₃·formal + β₄·notif
```

This is the analogue of expected firm profit in the BLP / Bertrand-Nash skill.

---

## 2. First-order conditions

Useful derivatives:
- ∂P/∂visits = α₁ · P(1−P)  (logit derivative)
- ∂Δu/∂visits = α₁
- Analogous for `formal` (α₂) and `notif` (α₃)

FOC w.r.t. `visits`:
```
∂E[C]/∂visits = β₅·α₁·P + (β₁·h + β₅·Δu)·α₁·P(1−P) + β₂ = 0
```
Rearranged:
```
−β₂/α₁ = (β₁·h + β₅·Δu_ct) · P_ct(1−P_ct) + β₅ · P_ct
```

FOCs w.r.t. `formal` and `notif` are identical in structure with (α₂, β₃) and (α₃, β₄) substituted.

---

## 3. Cross-equation restriction

The three FOCs imply:
```
−β₂/α₁ = −β₃/α₂ = −β₄/α₃ = (β₁·h + β₅·Δu_ct)·P_ct(1−P_ct) + β₅·P_ct
```
The RHS is identical across the three actions, so the data must satisfy:
```
β₂/α₁ = β₃/α₂ = β₄/α₃
```
at every observation, given α̂ from the demand step.

### Intuition
With linear additive regulator costs, the regulator equates marginal-action-cost-per-unit-of-CWS-utility-shift across all enforcement tools. If visits are cheap per unit of utility deterrent (β₂/α₁ small), the regulator does more visits, until marginal returns equalize across tools.

### If the restriction fails
It will almost certainly fail in raw form because linear additive costs are too restrictive. Three fallbacks, in order of cost:

1. **Convex action-specific costs.** Replace β_k · k with (β_k / 2) · k². FOCs become:
   ```
   β₂·visits + (β₁·h + β₅·Δu)·α₁·P(1−P) + β₅·α₁·P = 0
   ```
   The cross-equation restriction relaxes to β₂·visits / α₁ = β₃·formal / α₂ = β₄·notif / α₃ — more flexible, still testable.
2. **Action-specific fixed costs.** Add intercepts k_visit, k_formal, k_notif capturing fixed costs unrelated to behavior. Shifts the restriction additively.
3. **Reject linear/quadratic specification.** If both fail, regulator cost is genuinely non-separable or there's an unmodeled budget constraint. Move to constrained optimization — much harder.

---

## 4. Identification

Treat the `visits` FOC as a regression equation across observations, with α̂₁ taken from the demand step:
```
−β₂/α₁ = β₁·h · P_ct(1−P_ct) + β₅ · Δu_ct·P_ct(1−P_ct) + β₅ · P_ct
```

With cross-observation variation in P_ct and Δu_ct, identified coefficients are:

| Regressor | Coefficient |
|---|---|
| P(1−P) | β₁·h |
| Δu·P(1−P) | β₅ |
| P | β₅ |

So:
- **β₁·h** is identified as a scalar (under "h is constant across CWSs" assumption).
- **β₅** is over-identified — two moments for one parameter, a testable restriction.
- **β₂, β₃, β₄** are identified as scalar intercepts (one per FOC).

### What is not identified

- **β₁ and h separately.** They appear only as the product β₁·h. **Standard fix:** normalize β₁ = 1; interpret h in regulator-cost units. Convert to dollars later by an external calibration.
- **h_ct heterogeneity.** If h varies across CWSs (e.g., larger population served → higher social cost), β₁·h_ct enters as a per-observation unknown collinear with the other regressors. Either specify h_ct = γ'z_ct with z excluded from Δu, or treat h_ct as a fitted residual after constraining β's.

### The β₅ = 0 special case

If you assume the regulator does not internalize CWS surplus at all — defensible for SDWA where the EPA's mandate is health protection, not utility — then β₅ = 0 and the FOC simplifies to:
```
−β₂/α₁ = β₁·h · P_ct(1−P_ct)
```

This is cleaner but exposes a tension: with a scalar β₁·h and a scalar β₂, the FOC forces P(1−P) to be **constant across observations**, which is empirically wrong. The way out is one of:
- **h_ct varies** — relax the constant-h assumption (you lose scalar identification of h but gain consistency).
- **β_k varies by CWS type** — regulator cost differs by region, contamination type, etc.
- **Corner solutions** — many CWSs have visits = 0, so the FOC equality doesn't bind there; estimation uses only interior observations and a Kuhn–Tucker complementarity condition for corners.

This tension is a red flag for the constant-everything specification and points toward convex costs and/or h_ct heterogeneity from the start.

---

## 5. Estimation strategy — GMM

### Moment conditions
Three FOCs per observation:
```
g₁_ct(θ) = β₂ + (β₁·h + β₅·Δû_ct)·α̂₁·P̂_ct(1−P̂_ct) + β₅·α̂₁·P̂_ct
g₂_ct(θ) = β₃ + (β₁·h + β₅·Δû_ct)·α̂₂·P̂_ct(1−P̂_ct) + β₅·α̂₂·P̂_ct
g₃_ct(θ) = β₄ + (β₁·h + β₅·Δû_ct)·α̂₃·P̂_ct(1−P̂_ct) + β₅·α̂₃·P̂_ct
```
Parameters θ = (β₁·h, β₂, β₃, β₄, β₅) — five scalars.

Two-step GMM:
1. Pick instruments W_ct (functions of exogenous variables — IVs, state FE, year FE).
2. Minimize Q(θ) = [Σ g(θ) ⊗ W]' Ω̂⁻¹ [Σ g(θ) ⊗ W].

With 3 FOCs and W of dimension d, you get 3d moments and 3d − 5 over-identifying restrictions. Hansen J tests the model.

### Plug-in inputs
- α̂ from the CWS logit (MVP step) — note the cross-step uncertainty
- P̂_ct = exp(Δû_ct) / [1 + exp(Δû_ct)]
- Δû_ct from observed x_ct and α̂

### Inference
Two-step bootstrap. Inner: resample, re-estimate CWS logit (Step 1). Outer: re-estimate regulator GMM (Step 2). Both clustered at PWSID. The α̂ uncertainty matters for β̂; ignoring it understates SEs.

---

## 6. Equilibrium concept

**Definition.** A vector (visits*_ct, formal*_ct, notif*_ct, P*(MR | x*_ct)) such that:
1. **CWS best response:** P*(MR | x*_ct) = exp(α'x*_ct) / [1 + exp(α'x*_ct)]
2. **Regulator best response:** (visits*, formal*, notif*) minimizes E[C_ct] taking P* as given.

This is simultaneous Nash, the natural analogue of Bertrand-Nash.

### Existence
Brouwer's fixed-point theorem, provided:
- Action spaces are compact (impose bounds: visits ∈ [0, V_max], etc.)
- E[C_ct] is continuous in (visits, formal, notif) — true under linear or convex costs
- Best-response correspondence is upper hemi-continuous — true under continuity

### Uniqueness
Harder. Two practical routes:
- **Numerical.** Solve the fixed point from multiple starting points; check all converge to the same equilibrium.
- **Theoretical.** With logit demand and strictly convex regulator costs, contraction-mapping arguments give local uniqueness. State globally as a numerical observation backed by sensitivity checks.

### Timing
Specify simultaneous Nash, not Stackelberg, in writing. Stackelberg (regulator commits to rule, CWS responds) is a separate model with different FOCs (the regulator's FOC would include the CWS reaction function).

---

## 7. Counterfactuals — full equilibrium version

For each counterfactual, perturb the environment and re-solve the fixed point.

### Fixed-point loop (schematic)
```
Initialize (visits⁰, formal⁰, notif⁰) at observed values
Repeat until convergence:
  1. Δu = α₁·visits + α₂·formal + α₃·notif + α₄·cost_save
  2. P = exp(Δu) / (1 + exp(Δu))
  3. From regulator FOCs, solve for new (visits, formal, notif) given (P, Δu)
  4. Stop if max change < tolerance
```

### CF1 — Inspection budget shock
Lower β₂ (visits become cheaper per unit of regulator cost). Re-solve. Both regulator effort and CWS choice adjust.

### CF2 — Mandatory notification
Constrain notif_ct = 1 for all (c, t). Drop the notif FOC. Re-solve in (visits, formal). The regulator may substitute away from visits and formal action.

### CF3 — No upstream mining
Set the mining-driven component of cost_save → 0. Re-solve full system. Both CWS choices and regulator enforcement adjust.

### Welfare
Total social cost:
```
W_ct = β₁·ĥ · P*(MR | x*) + β₂·visits* + β₃·formal* + β₄·notif* + β₅·Δu* · P*(MR | x*)
ΔW   = Σ_ct [ W_ct(baseline) − W_ct(CF) ]
```
With β₁ = 1, W is in regulator-cost units. Convert to dollars via an externally calibrated value of one regulator-cost unit (e.g., EPA inspection cost from budget data).

---

## 8. Estimation order

1. **CWS logit with control function** (the MVP step). Recover α̂, λ̂.
2. **Compute P̂_ct, Δû_ct** from CWS logit.
3. **GMM on regulator FOCs.** Recover β̂₁·ĥ, β̂₂, β̂₃, β̂₄, β̂₅. Test cross-equation restriction via Hansen J.
4. **Equilibrium check.** Verify the implied fixed point reproduces observed (visits, formal, notif, P(MR)) at baseline. A major discrepancy rejects the model.
5. **Counterfactual fixed-point computation.** For each perturbation, iterate to convergence; bootstrap for SEs.

---

## 9. The four caveats

### (i) IV requirement
Need defensible IVs for visits, formal, notif (and cost_save) in step 1. Without them, α̂ is biased and β̂ inherits the bias. This is the hardest practical obstacle. The project currently has one strong instrument (ARP × `sulfur_unified`), which serves cost_save. Need three more — hunt for state-level enforcement budget shocks, EPA regional reorganizations, or neighboring-state spillovers.

### (ii) Cross-equation restriction
Test β₂/α₁ = β₃/α₂ = β₄/α₃ in the data. If it fails badly, linear additive cost is wrong. Move to convex costs (more realistic anyway).

### (iii) Normalization
β₁ = 1. State explicitly. Welfare numbers depend on the normalization and an externally calibrated dollar value per regulator-cost unit.

### (iv) Corner solutions
The FOC equality only holds for interior solutions. Many CWSs likely have visits = 0 in many years — the regulator chose not to inspect at all. Two responses:
- Use only interior observations for FOC-based estimation. Lose efficiency, may bias if corner status correlates with unobservables.
- Add a Kuhn–Tucker complementarity condition: for each action, either the FOC holds at equality or the action is at a corner with the gradient pointing into the constraint. This converts GMM into a system of inequalities and is harder to estimate.

If the share of corner observations is large (>50%), the FOC framework is the wrong tool. Switch to a regulator discrete-choice model: regulator picks (visits-level, formal-level, notif) from a discrete set, with choice probability = exp(−E[C]) / sum. Estimate via MLE on observed regulator actions. This is a richer model with cleaner foundations but substantially more work.

### Workability scorecard

| Caveat | Difficulty | Likelihood of clean resolution |
|---|---|---|
| (i) IVs for 3 regulator actions | Hard | Medium — depends on a data hunt |
| (ii) Cross-equation restriction | Medium | High — easy to test; convex-cost fallback is clear |
| (iii) Normalization + dollar calibration | Easy | High — standard |
| (iv) Corner solutions | Hard | Medium — depends on share of interior obs |

**Overall:** workable if (i) and (iv) clear. (ii) and (iii) are routine. If (i) or (iv) fails, the supply side is not estimable in this form, and either the MVP partial-equilibrium version is the ceiling, or the model becomes a regulator discrete-choice problem (which is feasible but a separate project).

---

## 10. Links

- MVP companion: `.claude/logs/2026-05-25-mvp-cws-logit-explainer.md`
- Template: `.claude/skills/counterfactual_structural_modelling_basics.md`
- Prior K&S attempt this would replace: `.claude/logs/2026-05-06-structural-model-analysis.md`
- Related N-and-variation diagnosis: `.claude/logs/2026-05-22-structural-regression-N-variation.md`
- Originating chat session: 2026-05-25
