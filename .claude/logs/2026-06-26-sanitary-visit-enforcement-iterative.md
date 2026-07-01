# Session: 2026-06-26 — sanitary-visit-enforcement-iterative

## Objective
Build a CWS-month panel (strictly-downstream 2SLS sample, 1985-2005) and run 3
cumulative LPM specs x 2 enforcement outcomes (formal/informal) testing
sanitary-visit timing, MR status, violation history, and SYR2 contaminant
concentration (% of MCL) against ongoing enforcement. One combined 6-column
table in output/reg/.

## Changes Made
- New: code/coal_mining_water_quality/sanitary_visit_enforcement_iterative.r
- New: output/reg/sanitary_visit_enforcement_iterative.tex

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| "The violation" anchoring visit_before6/after6/mr_violation = any onset that CWS-month | User said "the violation" without specifying category; mirrors mr_any construction in sanitary_visit_enforcement_lag.r |
| n_prior_violations = running count of all-category onsets strictly before current month, defined every month | Needed as a control independent of whether a violation starts this month |
| pct_mcl_last_max = running cummax of ratio, carried forward (roll join) | "last maximum contaminant concentration measured" read literally |
| Enforcement span = [month(ENFORCEMENT_DATE), month(coalesce(CALCULATED_RTC_DATE, NON_COMPL_PER_END_DATE, ENFORCEMENT_DATE))] | User-confirmed answer to AskUserQuestion on enforcement timing |
| No extra controls (e.g. num_facilities) | User specified exactly 5 regressors; don't add unrequested controls |

## Verification Results
- [ ] Script runs end-to-end
- [ ] Output exists at expected path
- [ ] Row counts plausible

## Open Questions / Blockers
- None outstanding; assumptions above were stated in the plan and approved.

## Next Steps
- Implement script, run, verify, report.
