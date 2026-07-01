# Session: 2026-06-30 — Sanitary visit timing vs. enforcement design

## Objective
Understand and critique the coding of `output/reg/sanitary_visit_enforcement_iterative.tex`
(from `code/coal_mining_water_quality/sanitary_visit_enforcement_iterative.r`), then evaluate
a proposed recoding meant to test whether regulators deploy sanitary visits preemptively
(before suspected violations) vs. reactively (after a violation onset).

## Changes Made
- None — discussion/methodology only, no files edited this session.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Rejected user's proposed recoding (extend `visit_before6`/`visit_after6` to span all months enforcement is active) | Ties the RHS regressor's support to the same enforcement-spell timeline used to build the DV (`enf_formal_ongoing`/`enf_informal_ongoing`), producing mechanical/tautological correlation rather than evidence about visit timing relative to onset. |
| Recommended alternative: make the sanitary visit itself the dependent variable in an event-study around violation onset (lead/lag dummies relative to `onset_dt`, CWS + month FE) | Directly targets the preemptive-vs-reactive question: rising visit probability in lead months = preemptive targeting; rising probability in lag months = reactive follow-up. Also suggested a simpler purely descriptive check (fraction of onsets with visit strictly before vs. strictly after). |

## Verification Results
- N/A — no code run this first session.

---

## Update: 2026-06-30 (continued) — sanitary_visit_to_enforcement.tex redesign

### Objective
Redesign `output/sum/sanitary_visit_to_enforcement.tex` so that:
1. The unconditional probability column = share of CWS-month cells with a given enforcement type (formal or informal), not visit-type frequency as before.
2. Pre/post columns = P(visit group occurs in ±6 months | enforcement event), conditioning on enforcement events rather than MR violation onsets.
3. Two-panel structure: Panel A = formal enforcement, Panel B = informal enforcement.

Motivation: the unconditional probability of enforcement is the correct baseline denominator for interpreting regression coefficients in `sanitary_visit_enforcement_iterative.tex` (e.g., a 0.22 pp coefficient on `visit_lag` relative to a 0.27% formal-enforcement base rate implies ~81× the mean).

### Changes Made
- `code/coal_mining_water_quality/sanitary_visit_enforcement_lag.r`: replaced section 8 (Q1 timing table) with `enf_visit_rows()` function that conditions on enforcement events (`enf_formal`/`enf_informal`) instead of MR violation onsets. Two-panel LaTeX output; unconditional probability is now `mean(skel[[enf_col]])`.
- `output/sum/sanitary_visit_to_enforcement.tex`: regenerated. Key numbers: formal enforcement unconditional prob = 0.27% (N=183 events), informal = 2.40% (N=1,996). Sanitary visits preceded 12.6% of formal enforcement events and 9.6% of informal enforcement events within 6 months.

### Verification Results
- [x] Script runs end-to-end (exit 0)
- [x] Output file regenerated and non-zero
- [x] Numbers pass sanity check: formal enforcement is rare (0.27%), informal is ~9× more common (2.40%); sanitary visit pre-probability is higher for formal than informal, consistent with visits being informative about serious violations

## Open Questions / Blockers
- None active.

## Next Steps
- None specified; user may want to reference the unconditional probabilities in the paper text.
