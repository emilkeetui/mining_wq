# Session: 2026-10-22 — k2 updn tables in JMP

## Objective
Add the two-endogenous-regressor (upstream + downstream mines; z_up, z_dn) k2 tables to job_app_jmp.tex.

## Changes Made
- job_app_jmp.tex: new subsection "Two endogenous regressors: upstream and downstream coal mines" after the over-id block, inputting 7 `_k2updn` tables.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| No new R code | run_k2_updn_tables.r already estimates this spec |

## Verification Results
- [x] run_k2_updn_tables.r exits 0; git diff of output/reg/*k2updn* empty (reproduces)
- [x] Anchor gate 565 utilities / 10,641 obs
- [x] Downstream 2SLS coef significant at 10% in 0 of 29 columns
- [x] First-stage joint F: upstream 19.95-24.68, downstream 17.50-18.31
- [x] latexmk compile: exit 0, no errors, no undefined/duplicate refs, 0 overfull boxes

## Open Questions / Blockers
- Joint F is not Sanderson-Windmeijer/Kleibergen-Paap (removed in 80090c2).
- No body text cites the new tables.

## Next Steps
- Commit and merge after user approval.
