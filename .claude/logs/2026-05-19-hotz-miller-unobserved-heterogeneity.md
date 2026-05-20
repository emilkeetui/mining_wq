# Session: 2026-05-19 — H–M vs A–M for unobserved heterogeneity in Section 3

## Objective
User flagged that Aguirregabiria–Mira (2010, p.15) state Hotz–Miller CCP cannot
accommodate permanent unobserved heterogeneity. Asked whether this is fatal
given plausible permanent UH across CWSs (e.g., political power).

## Discussion / Decision
- Not fatal. The 2026-05-07 structural-explainer log already anticipated this
  (lines 240–253, 382–386): if PWSID FE in an OLS of MR-share explains R² ≥ 0.3,
  escalate to Arcidiacono–Miller (2011) EM extension.
- Mechanism of bias if ignored: empirical Pr(MR|s) within a cell is a mixture
  of type-specific CCPs weighted by type composition; log-odds regression then
  conflates "effect of state s" with "type composition of cell s" → biased k_MR.
- A–M fix: EM over discrete latent types; type-specific CCPs and k_MR
  re-estimated weighted by posteriors. Feasible with 1985–2005 panel
  (~20 yrs/PWSID), 8 state cells, ~780 obs/cell. 2 types tractable; 3+ strains data.
- Recommended: make A–M the **default** rather than contingency, because
  political-economy heterogeneity (Konisky etc.) is a priori plausible and a
  referee will raise it. Cheaper to address now than at R&R.

## Open Questions
- Re-run the PWSID-FE R² diagnostic on the cleaned panel before committing to
  A–M as primary vs. fallback.
- Time-varying political power is outside the A–M frame (permanent types only).
  Defensibility of "permanent over 1985–2005" assumption for CWSs needs a
  short justification in the paper.

## Next Steps
- Update Section 3 plan to flip A–M from "conditional citation" to "primary
  estimator" pending the R² diagnostic.
- Add the diagnostic as an early step in the structural-estimation script.
