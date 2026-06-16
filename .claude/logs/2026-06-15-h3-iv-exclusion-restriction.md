# Session: 2026-06-15 — H3 2SLS exclusion restriction assessment

## Objective
Assess validity of user's concern that the instrument (post95 × upstream_sulfur)
in `output/reg/h3_inf_formal_d12.tex` violates the exclusion restriction via an
omitted water-pollution variable. Outcome = formal/informal regulator action;
endogenous regressor = upstream coal mines.

## Key Analysis / Conclusions
- **Concern is misplaced for the current spec (Setup 1: instrument mining).**
  Pollution is a *mediator* on the path mining → pollution → regulator action,
  not an independent channel. Exclusion restriction = "Z affects Y only through D";
  mediators of D's effect are allowed (controlling for them = bad control).
  Estimand = total effect of mining on regulator action.
- **Real Setup 1 threats** are non-mining paths from post95×sulfur to regulators:
  (1) sulfur leaching/acid drainage without mining; (2) post95 policy bundling
  (ARP SO2 air policy, regional enforcement shifts) hitting high-sulfur regions;
  (3) any direct Z→Y path.
- **Setup 2 (user's proposal: instrument violations, regress regulator action on
  violations)** is the spec that DOES have the exclusion problem the user intuited:
  coal mining becomes the omitted variable in the second-stage error and is
  strongly correlated with Z. Valid only if mining touches regulators *only*
  through measured violations (dubious — mine salience, unmeasured contaminants).
- Setups 1 and 2 are **different estimands**, not better/worse versions. One
  instrument identifies one of them; Setup 2 needs a *stronger* exclusion
  assumption, not weaker.

## Open Questions / Next Steps
- Which estimand does the user actually want for H3: effect of *mining* on
  regulator behavior (Setup 1) or effect of *pollution* on regulator behavior
  (Setup 2)?
- If Setup 1: propose placebo first stage (no mining → no sulfur effect) +
  ARP air-policy controls.
- Have not yet read the actual table/generating script — pending user's choice
  of estimand.

---
**[COMPACTION NOTE � 2026-06-16T03:33:53Z]**  
Auto-compact triggered. Active plan: `none`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---
