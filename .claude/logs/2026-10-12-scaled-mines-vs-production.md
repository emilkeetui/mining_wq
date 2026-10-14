# Session: 2026-10-12 — scaled-mines-vs-production

## Objective
Implement plan standardized-elasticity-mines-vs-production-comparison.md: re-estimate six k2
tables with upstream mine count vs upstream coal production on SD-standardized and elasticity
(at means; log1p secondary) scales, with stacked equality tests and comparison tables/CSV.

## Changes Made
- k2_common.r: `digits = 2` arg on render_panel_k2 (default keeps callers identical).
- run_k2_scaled_comparison.r: new script (all new outputs).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Committed pre-existing WIP (k2_common.r, run_k2_6yr_tables.r, run_k2_main_tables.r) on step23-sample, then branched scaled-mines-vs-production | User chose "commit WIP first"; plan assumed clean master |
| Elasticity at means primary; log1p secondary | 61% zeros in x; log1p is unit-dependent (Chen & Roth) |
| RF rows identical between mines/prod versions | only y rescaled; expected |
| 6yr: refit on obs(level model) so scaling stats use exact estimation sample | plan 2b |

## Verification Results
- [ ] Script runs end-to-end
- [ ] Output exists at expected path
- [ ] Row counts plausible

## Open Questions / Blockers
-

## Next Steps
- Await user approval before /commit
- Stable-sample screen alone gives 10,650 obs/574 utilities; the parents' 10,641/565 also drop 9 single-observation utilities (fixest singleton PWSID FE). Added that drop to the new script so scaling moments use the exact estimation sample.
- Script ran, exit 0, 453 gates PASS (anchors 3.94/19.39, 0.0022/0.0001; identities; stacked coefs; F invariance; no F<10). All 26 tex + CSV written; all compile (26-page test PDF, no errors/overfull).
- Correction: 6yr scaled tables first used \raggedright float alignment; parent uses \centering (memory: latex float centering). Fixed in script and patched output files in place.
- Result: 2SLS mines/prod ratio is identical across outcomes within a table (just-identified: ratio of first-stage coefs). SD ratio 0.501, elasticity 0.823 (MR). close: SD 15/21, elas 15/21, log 18/21.
