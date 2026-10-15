# Session: 2026-10-15 — k2 mines vs production scaled figures

## Objective
Replace scaled_compare_elas_k2.tex with figures comparing the mines and annual-production regressors (SD units, elasticity at means). Plan: ~/.claude/plans/k2-mines-vs-production-scaled-figures.md

## Decisions
| Decision | Rationale |
|----------|-----------|
| Scalings z and m only; drop log | log1p(production in mst) is unit-dependent |
| 2SLS state x year rows; SYR2 panel B annual OLS | matches the table |
| Ring work committed (20abc42), new branch k2-mines-vs-production-figures | user choice |

## Verification Results
(see below)

- run_k2_scaled_first_stage.r: exit 0, all 4 gates pass (F mines 49.2, F prod 11.8, ratio identity for both scalings). First-stage pi negative for both (mines -0.493, prod -0.100): ARP cut mining/production in high-sulfur areas, as expected.
- plot_k2_scaled_compare.r: exit 0; anchor + constant-ratio gates pass; 4 PNGs written. Fixed overlapping panel titles (two-line titles) and first-stage x labels (wrapped).
- Every 2SLS point lies on the first-stage line by construction. SYR2 (panel B): selenium opposite signs (mines -0.083, prod 0.046); all CIs wide.
- main.tex: table line removed, new subsection with 4 figures before "Coal mines downstream"; latexmk exit 0, no errors, no ??, figures on pp. 58-61.
- Not committed (awaiting user confirmation).
