# Session: 2026-10-07 — placement-week scaled tables

## Objective
Placement-week slide versions of the MR-violation, enforcement-type, and visit-type k2 tables:
N rows moved to notes, mine coefficients scaled by the mean upstream mine count, OLS/RF dropped
from the enforcement and visit tables.

## Changes Made
- code/coal_mining_water_quality/run_k2_placement_tables.r (new): writes `*_placement.tex` for
  2sls_dwnstrm_minevio_mr_ivsum_binvio_k2, h3_inf_formal_d12_k2, h2_snsv_d12_k2.
- placement_week.tex: new `\placereg` macro (-> `_placement.tex`); three frames switched to it;
  takeaways updated (formal enforcement 3.4 -> 3.8 pp, inspections 2.1 -> 2.4 pp).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Scale = unconditional mean of num_coal_mines_linked_sum over the 2SLS sample (1.1212) | "Average treatment" in the estimation sample; mean conditional on >0 is 2.85 (alternative) |
| RF in MR table left unscaled | RF regressor is the instrument, not mines |
| h2 FE rows dropped, FEs stated in notes | Uniform FE across columns (formatting Rule 7) |
| New script, not edits to render_panel_k2 | Leaves paper/job-talk tables untouched |

## Verification Results
- [x] Script runs end-to-end; MR anchor gate (3.94/1.75 unscaled) passes
- [x] Outputs exist; N = 565 utilities / 10,641 obs
- [x] placement_week.tex compiles, no errors/undefined refs; slides 12, 14, 15 inspected

## Open Questions
- Whether the user prefers the conditional-on-positive mean (2.85) as the scale.
- 2026-10-07 (later): user asked to remove the mean-mine scaling; placement tables now show per-mine coefficients (identical to paper tables), label back to 'Upstream coal mines (sum)', takeaways reverted to 3.4 / 2.1 pp. Deck recompiled OK.
