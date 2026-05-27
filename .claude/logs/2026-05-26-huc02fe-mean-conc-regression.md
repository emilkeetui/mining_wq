# Session: 2026-05-26 — HUC02×Year FE regression on 6yr mean concentrations

## Objective
Implement the regression from page 12 of Coal_Mining_Drinking_Water_2026.pdf
on the 6-year-review dataset with mean analyte concentration as the outcome.

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| HUC02 × year FE (interacted) | Matches slide spec γ_hy |
| D = cumsum of upstream production since 1985 | User choice; panel start year |
| Downstream-only sample | Matches existing 2sls script |
| Modal HUC02 fallback for multi-HUC02 PWSIDs | 0 collisions in downstream sample; 2 in full sample |
| X_say (monthly controls) omitted | Already collapsed in parquet; noted in footnote |

## Changes Made
- Plan written: `Z:/Users/ek559/.claude/plans/huc02-fe-6yr-mean-concentration-regression.md`
- No code written yet (plan approved, pending implementation)

## Open Questions / Blockers
- None; plan approved, ready to implement

## Next Steps
- Write `code/coal_mining_water_quality/cws_intake_huc02.py`
- Write `code/coal_mining_water_quality/cws_6year_review_huc02fe.r`
- Run both scripts and verify outputs
