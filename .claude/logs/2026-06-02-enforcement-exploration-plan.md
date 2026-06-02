# Session: 2026-06-02 — Enforcement in Mining Areas: Reduced-Form Exploration Plan

## Context

The K&S binary structural model produced δ_μ[mining] < 0 persistently across all κ ∈ [0.1, 0.8] and all attempted model variants. This is economically implausible as a compliance cost parameter and has no satisfactory modelling fix (see §19 of the structural proposal log). The model is abandoned.

The enforcement laxity finding is robust: mining areas receive significantly less formal enforcement (h3 2SLS: −0.087***, feols probit φ_m = −0.360). The question is whether this is a between-state pattern (mining states like WV/KY/VA have weaker EPAs) or a within-state pattern (within mining states, areas with more mines get less enforcement).

---

## Open Question

**Is enforcement laxity in mining areas a between-state or within-state result?**

Mining is geographically concentrated in WV, KY, VA, eastern OH — states with historically weaker state EPA capacity and closer political ties to coal. The raw `cor(mining, Δê_formal) = −0.137` is unconditional. How much survives within-state?

---

## Recommended Analyses (Priority Order)

### 1. Summary table: enforcement rates by HUC type (30 min)

Cross-tab mean formal enforcement rate, informal enforcement rate, and days-to-RTC across `minehuc` categories (mine, upstream, downstream, non-mining) — raw and within-state (subtract state-year cell means). If the gap between mining and non-mining HUCs shrinks substantially after within-state demeaning, enforcement laxity is between-state. If it persists, it is within-state.

### 2. OLS decomposition: within vs. between state (1 hour)

Run three regressions of formal enforcement indicator on `log(1 + num_coal_mines_upstream)`:
- No FEs (raw association)
- State FE only
- PWSID + year + state FEs (same spec as main paper)

The coefficient path from spec 1 → 2 → 3 decomposes the mining-enforcement relationship into between-state, between-PWSID within-state, and within-PWSID over-time components.

### 3. Reduced form: ARP instrument on enforcement outcomes (2–3 hours)

Swap enforcement as the dependent variable in the same reduced-form spec as the main paper:

```
formal_enf_it = α(sulfur_h × post95_t) + η_PWSID + τ_year + ρ_state + ε_it
```

Run for: formal_enf, informal_enf, days_to_RTC_formal, days_to_RTC_informal.

A negative α means enforcement fell when mining fell exogenously — enforcement tracks mining, consistent with regulatory capture. Near-zero α means raw correlation is compositional (between-state).

### 4. 2SLS: causal effect of mining on enforcement (builds on 3)

Instrument `num_coal_mines_upstream` with `post95 × sulfur_unified`, outcome = formal enforcement. Gives a clean causal estimate of whether more mining causes more or less enforcement — the regulatory-side analog of the main paper result.

---

## Suggested Presentation

These analyses would form a mechanism/robustness section of the paper:

> "Mining areas receive less formal enforcement, driven partly by state-level regulatory capacity differences and partly by within-state patterns, as shown by the reduced form of enforcement on the ARP instrument."

Combined with the main 2SLS on violations, this is a two-part story: mining raises violations (main result) and attenuates the regulatory response (mechanism).

---

## Files to Create

- `code/coal_mining_water_quality/enforcement_mining_rf.r` — analyses 1–4 above
- `output/reg/enf_decomp.tex` — OLS decomposition table (analysis 2)
- `output/reg/enf_rf.tex` — reduced-form and 2SLS on enforcement outcomes (analyses 3–4)
- `output/sum/enf_by_huctype.tex` — summary table (analysis 1)

---

## Status

- [ ] Analysis 1: summary table by HUC type
- [ ] Analysis 2: OLS decomposition
- [ ] Analysis 3: reduced form on enforcement
- [ ] Analysis 4: 2SLS on enforcement
