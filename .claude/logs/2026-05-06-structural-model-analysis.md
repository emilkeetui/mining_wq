# Structural Model Analysis: Revised Plan
## Session: 2026-05-06 | Updated: 2026-05-07 after Priority 0 feasibility checks

---

## Objective

Adapt the Kang & Silveria (2021) / Mookherjee-Png (1994) structural model of
regulator–firm enforcement interactions to the coal mining × drinking water quality
setting. Recover the implicit cost CWSs place on monitoring/reporting violations
(k_MR) and use it to simulate counterfactual enforcement regimes.

---

## Feasibility

### Priority 0 Results — `code/coal_mining_water_quality/priority0_feasibility.r`
**Run: 2026-05-07**

**Sample:** Downstream-only CWSs
- Filter: `minehuc_downstream_of_mine == 1 & minehuc_mine == 0`, years 1985–2005, drop `WV3303401`
- N = 6,232 PWSID×year observations; 340 unique PWSIDs
- Coal variable: `num_coal_mines_upstream`; instrument: `post95 × sulfur_unified`

---

**Check 1: Enforcement chain density — NOT FEASIBLE as originally specified**

| Metric | Count |
|--------|-------|
| PWSIDs with any enforcement record | 268 / 340 |
| PWSIDs with complete chains (informal + formal + RTC) | 111 |
| PWSIDs with ≥2 enforcement state transitions | 234 |
| Markov MLE feasibility threshold | 500 |

MR dominates violation records (17,227 MR vs. 949 MCL, 875 TT). Days-to-RTC: median 183, mean 332, IQR [89, 364].

**Verdict:** 234 PWSIDs is below threshold. 4-state Markov MLE not feasible. **Collapse to 2-state machine:** {no active enforcement} ↔ {any enforcement action}.

---

**Check 2: Sanitary survey coverage — USABLE as covariate only**

| Metric | Count |
|--------|-------|
| SNSV records (1985–2005) | 1,042 |
| PWSIDs with ≥1 sanitary survey | 270 / 340 |
| PWSIDs surveyed in ≥5 years | 64 |

Coverage collapses 1992–1998, likely reflecting SDWA 1996 Amendments implementation.

**Verdict:** Too sparse for annual state variable. **Use as time-invariant covariate:** total surveys / years in sample.

---

**Check 3: MCL vs. MR granularity — MCL TOO SPARSE for CCP identification**

| Metric | Count |
|--------|-------|
| PWSIDs with any MCL > 0 (any mining contaminant) | 15 / 340 (4.4%) |
| PWSIDs with any MR > 0 (any mining contaminant) | 170 / 340 (50%) |
| PWSIDs with both MCL > 0 and MR > 0 | 9 across all contaminants |

MCL nonzero observations: 4–20 per contaminant out of 6,232. MR nonzero: 250–377 per contaminant.

**Verdict:** MCL/MR cost ratio **not identified** from this sample. **Drop MCL from choice set.** Model CWS as choosing over {comply, MR violation} only. Check colocated sample separately for MCL identification.

---

**Check 4: First-stage and reduced form — INSTRUMENT IS STRONG; MR DRIVES ALL VARIATION**

First stage: coefficient = −0.0822 (SE = 0.0223, t = −3.69), **F = 13.6** — above weak-instrument threshold.

| Outcome | Coeff | SE | t-stat | Estimable |
|---------|-------|----|--------|-----------|
| nitrates_MCL_share_days | — | — | — | No (< 10 nonzero obs) |
| arsenic_MCL_share_days | — | — | — | No |
| inorganic_chemicals_MCL_share_days | +0.460 | 0.445 | +1.03 | Yes (not sig.) |
| radionuclides_MCL_share_days | — | — | — | No |
| nitrates_MR_share_days | −4.938 | 2.234 | **−2.21** | Yes |
| arsenic_MR_share_days | −3.699 | 1.984 | **−1.87** | Yes |
| inorganic_chemicals_MR_share_days | −3.582 | 2.072 | **−1.73** | Yes |
| radionuclides_MR_share_days | −0.156 | 2.719 | −0.06 | Yes (not sig.) |

Total and MR coefficients are nearly identical — MCL contributes essentially zero to total violation variation.

**Verdict:** Instrument is strong (F = 13.6). The ARP shock identifies the MR margin only. Structural identification of k_MR is feasible; k_MCL is not.

---

**Revised Feasibility Summary**

| Component | Original plan | Revised assessment |
|-----------|--------------|-------------------|
| Regulatory machine | 4-state Markov MLE | **2-state machine** {no_enf / enf} |
| CWS choice set | {comply, MR, MCL} | **{comply, MR} only** — MCL too sparse |
| Structural parameters | k_MR / k_MCL ratio | **k_MR alone** |
| First-stage strength | Strong for total violations | **Confirmed F = 13.6**, MR only |
| Sanitary survey state | Time-varying annual rate | **Time-invariant covariate** |
| Counterfactuals | MCL and MR enforcement | **MR enforcement only** |

---

## Scope

The structural goal narrows from recovering k_MR / k_MCL to recovering **k_MR alone** — the implicit cost CWSs place on a monitoring/reporting violation. This is identified from:

- Binary CWS choice {comply, MR violation}, with observed MR violation shares as choice probabilities by contamination state
- 2-state enforcement machine {no enforcement / any enforcement} estimated from 268 PWSIDs
- ARP × sulfur instrument as a control function for contamination endogeneity

The normative question becomes: given the enforcement environment CWSs actually face, is k_MR large enough to constitute real deterrence? A k_MR near zero means CWSs treat monitoring violations as nearly costless. A k_MR near the compliance cost means enforcement is working.

The paper cannot deliver:
- k_MCL / k_MR cost ratio (MCL too sparse in downstream sample)
- Within-PWSID MCL vs. MR substitution (no within-PWSID MCL/MR variation)
- Full 4-state enforcement machine (only 111 complete chains)

The narrowing is not a failure — MR violations are precisely where the strategic substitution mechanism operates, and the downstream sample's data pattern (50% of CWSs have MR violations, 4.4% have MCL violations) is itself consistent with the theory.

---

## Paper Structure

### Section 1 — Theory (K&S / Mookherjee-Png, static)

Four propositions derived from the CWS's FOC: θ·b'(a(θ)) = e'(a(θ)).

- **P1 (type sorting):** ∂a/∂θ > 0 — higher-compliance-cost CWSs choose more MR violations. Tested via heterogeneity by CWS size and source water type.
- **P2 (enforcement deterrence):** ∂a/∂λ < 0 — higher enforcement intensity reduces MR violations. Operationalized via the enforcement machine counterfactual.
- **P3 (mining externality as type shifter):** ∂a/∂m > 0 — more mining raises effective compliance cost θ(m), increasing equilibrium MR violations. This is the structural grounding for the 2SLS result.
- **P4 (optimal convexity):** ε''(k) > 0 at optimum — normative benchmark for the MR enforcement schedule.

Remark in theory section: "We focus empirically on the MR margin, where the instrument provides clean identification." The choice-set narrowing is addressed in the empirical section, not the theory.

No changes required from original plan. All propositions hold regardless of whether k_MR alone or the k_MR/k_MCL ratio is identified.

### Section 2 — Reduced Form (2SLS, ARP × sulfur instrument)

Existing 2SLS tables stand. Two additions to motivate the structural model:

1. **MCL vs. MR reduced-form split** — formal table showing the instrument moves MR violations (t ≈ 2.0–2.2 for nitrates and arsenic) but not MCL violations (t ≈ 1.0, inestimable for 3 of 4 contaminants). Motivates binary-choice structural model.

2. **Enforcement intensity heterogeneity** — split reduced-form sample by enforcement intensity quartile (fraction of 1985–2005 years with any enforcement action). Test whether mining → MR violation effect is larger in low-enforcement areas. Reduced-form test of K&S mechanism.

### Section 3 — Structural Estimation (2-state machine, binary CCP)

**Step 1: 2-state regulatory machine**

State space: {`no_enf`, `enf`}. Transition matrix estimated by counting state transitions across 268 PWSIDs with enforcement records. Forward-simulate V₀(s) for s ∈ {no_enf, enf} under β = 0.95. Allow transitions to vary by enforcement intensity quartile.

**Step 2: CCP identification of k_MR**

Binary logit CCP identifying equation:

```
log[ Pr(MR | s, z) / Pr(comply | s, z) ] = (k_comply − k_MR)/σ_ε
                                           + (β/σ_ε) · [V₀(enf) − V₀(no_enf)] · Δπ(s)
                                           + γ · v̂_t
```

Contamination state: quartiles of `production_short_tons_coal_upstream` → 4 states × 2 enforcement states = 8 cells (~780 obs/cell). Control function residual v̂_t absorbs contamination endogeneity.

Two-type Arcidiacono-Miller heterogeneity invoked only if R² from PWSID FE regression in MR share OLS is ≥ 0.3.

### Section 4 — Counterfactuals

**Counterfactual 1: Double MR enforcement transition probability (quantifies P2)**
Increase π(enf | no_enf) by 100%. Recompute V₀ and optimal CWS choices. Report change in MR violation share by contamination quartile and aggregate person-weighted violation-days.

**Counterfactual 2: Targeted enforcement for high-contamination CWSs**
Compare compliance between top- and bottom-quartile enforcement intensity CWSs. Simulate low-enforcement area violation rates under high-enforcement intensity.

**Counterfactual 3: K&S-optimal convex MR penalty schedule (normative P4)**
Compute optimal ε*(k) from recovered k_MR and 2-state machine. Compare to observed schedule. Report compliance gain and fraction attributable to schedule shape vs. enforcement intensity.

---

## Paper Outcomes

| Result | Mechanism | Source |
|--------|-----------|--------|
| Mining increases MR violations (causal) | P3: mining → θ(m) → a*(θ) | 2SLS tables, existing |
| Instrument hits MR margin only (MCL near-zero) | Data pattern, Check 4 | Reduced-form table, new |
| k_MR recovered: implicit cost of MR violation | Binary CCP + 2-state machine | Section 3 |
| Mining → MR effect larger in low-enforcement areas | P2 cross-section test | Enforcement intensity split, new |
| Doubling MR enforcement → X% reduction in violations | P2 quantified | Counterfactual 1 |
| Observed MR schedule is suboptimal (subconvex) | P4 normative | Counterfactual 3 |

---

## Publication Venues

| Venue | Fit | Rationale |
|-------|-----|-----------|
| **Journal of Public Economics** | **Very strong — primary target** | Environmental enforcement + regulatory failure + clean quasi-experiment; structural grounding separates from reduced-form SDWA papers |
| **AEJ: Applied Economics** | Strong | Binary-choice structural + IV is the AEJ:Applied archetype; lower model complexity is fine here |
| **JEEM** | Strong fallback | Natural home for environmental enforcement structural models |
| **AEJ: Policy** | Strong fallback | Concrete policy counterfactuals; accessible framing |
| **AER** | Not realistic | Requires k_MCL/k_MR ratio + full multi-stage model |
| **JPE** | Not realistic | Requires full two-stage targeting + abatement identification |

**Submission framing:**
*"We show that quasi-experimental variation in CWS pollution burden — induced by the 1990 Clean Air Act Acid Rain Program — identifies the implicit cost CWSs place on monitoring/reporting violations. Using a binary dynamic discrete choice model with a two-state enforcement machine estimated from SDWA administrative records, we recover this structural compliance cost and use it to simulate counterfactual enforcement regimes."*

The advantage over Duflo et al. remains: clean quasi-experimental identification of the regulated entity's cost parameters, without a randomized experiment. The narrower, more tightly identified model is a feature for JPublicEcon and AEJ:Applied.

---

## Priorities and Next Steps

### Priority 0 — COMPLETE
All four feasibility checks complete as of 2026-05-07. Results incorporated above.

### Priority 1 — Theory (no data needed)

- [ ] **Write theory section (P1–P4).** Adapt K&S / Mookherjee-Png to SDWA setting. Derive Propositions 1–4 formally with proofs. ~6–8 pages. Can be drafted now.
- [ ] **Read Mookherjee and Png (1994).** PDF at `.claude/skills/Mookherjee and Png 1994.pdf`. Needed to cite correct source for P4's convexity result.

### Priority 2 — Reduced-form additions (~1 week)

- [ ] **MCL vs. MR reduced-form table.** Add to `run_main_tables.r`: separate columns for MCL and MR violation share, downstream sample. Use Check 4 results as template.
- [ ] **Enforcement intensity heterogeneity table.** Construct PWSID-level enforcement intensity (fraction of 1985–2005 years with any enforcement action). Interact 2SLS spec with enforcement intensity quartiles.
- [ ] **Check MCL incidence in colocated sample** (`minehuc_mine == 1`). If meaningfully higher, k_MCL identification may be recoverable for that subsample as a robustness/extension.

### Priority 3 — Literature

- [ ] **Ryan (2012) JPE** — static theory + dynamic estimation archetype; Clean Air Act attainment instrument analogous to ARP × sulfur.
- [ ] **Hotz and Miller (1993) RES** — core reference for CCP estimator.
- [ ] **Arcidiacono and Miller (2011) Econometrica** — CCP with unobserved heterogeneity via EM algorithm.
- [ ] **Rust (1987) Econometrica** — conceptual foundation for the DDC / Bellman approach.

### Priority 4 — Model specification decisions (required before coding)

- [ ] **Confirm state space:** 4 contamination bins × 2 enforcement states = 8 states.
- [ ] **Confirm discount factor β = 0.95** (calibrated, not estimated jointly).
- [ ] **Check R² from PWSID FE regression** in MR share OLS to decide on Arcidiacono-Miller.

### Priority 5 — Structural coding (after reduced-form additions confirmed)

- [ ] **`structural_penalty_machine.r`** — 2-state Markov MLE, V₀(s) forward simulation.
- [ ] **`structural_ccp.r`** — binary logit CCP, control function IV, k_MR recovery.
- [ ] **`structural_counterfactuals.r`** — three counterfactuals, compliance gains in violation-days and person-weighted exposure.
