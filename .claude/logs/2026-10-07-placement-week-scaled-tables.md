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

## Follow-up: placement_week.tex edits
- Removed the two upstream-radius (k-grid) backup slides (concentration, MR) and their links on slides 7 and 12.
- Typo/grammar pass (fragments kept as fragments).
- Added baseline rates (estimation-sample means, same as MR base rates on slide 12): inspection 3.4% (slide 14); informal 18.3%, formal 2.9% enforcement (slide 15).
- Compiled: 23 pages, no errors.
- LATE scaling added to 2SLS takeaways (slides 12, 14, 15): beta x first-stage x SD(sulfur) = RF x SD(sulfur); SD(sulfur)=1.13, first stage -0.49 (state x year) / -0.41 (year FE).
- User asked to remove LATE scaling (sign reversal undesirable); reverted.
- Re-added instrument-sized scaling with positive framing: effect of the 0.56 (0.47 year FE) extra mines a 1-SD lower-sulfur watershed kept after 1995.

## 6yr inorganic table — placement version (Panel B, mean-scaled)
- run_k2_6yr_tables.r now writes 6yr_huc02fe_inorg_ravalli_2005_k2_placement.tex: Panel B (within two flow steps) only, no subtitle, HUC02 -> "watershed" in notes, new caption.
- Dose divided by per-column estimation-sample mean, so coefs = effect of average cumulative upstream production since 1985; "Sample mean (million short tons)" row (arsenic 6.9, nitrate 8.6, barium 6.7, selenium 6.7).
- placement_week.tex slide uses \presregp; takeaway updated: nitrate +0.076 mg/L (9.4% of mean), selenium +0.0003 mg/L (6.9% of mean). Old selenium 8.5% did not reconcile with estimation-sample mean (implied ~10.3% unscaled) — flagged to user.
- User switched units: placement table now per 1 million short tons (10M ST coef / 10; digits r5), mean-scaling dropped; sample-mean row (M ST) kept; notes = FE + clustering + stars only; caption drops "average". Takeaway: nitrate +0.0088 mg/L per 1M ST (1.1% of mean), selenium +0.00004 (1.0%).
- User reverted request to 10M ST mid-run (edit was undone before running); kept per 1M ST. Column headers now carry units: "Arsenic (mg/L)" etc.
- Added "MCL (mg/L)" row to placement table: arsenic 0.050 (pre-2006 MCL, matches 1998-2005 sample), nitrate 10.000, barium 2.000, selenium 0.050; 3 decimals throughout the row.
- Takeaway now at sample-mean tons: nitrate +0.076 mg/L (9.4% of mean; 0.008831 x 8.6M), selenium +0.0003 mg/L (6.9%; 0.0000396 x 6.7M). Values from the earlier mean-scaled run (exact means).
