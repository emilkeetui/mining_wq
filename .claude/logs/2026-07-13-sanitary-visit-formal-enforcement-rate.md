# Session: 2026-07-13 — sanitary-visit-formal-enforcement-rate

## Objective
Build a 3-row CWS-year rate table: (1) formal enforcement rate across all
downstream 2SLS panel CWS-years, (2) rate among CWS-years with an MR
violation, (3) rate among CWS-years with an MR violation AND a same-year
sanitary visit. Tests whether sanitary visits substitute away from formal
enforcement following MR violations.

## Key context
- Sample: strictly-downstream CWSs (`minehuc_downstream_of_mine==1 & minehuc_mine==0`)
  from clean_data/cws_data/prod_vio_sulfur.parquet.
- Formal enforcement = ENF_ACTION_CATEGORY == "Formal" spell (SDWA_VIOLATIONS_ENFORCEMENT.parquet),
  collapsed CWS-month -> CWS-year via any().
- MR violation = VIOLATION_CATEGORY_CODE == "MR" onset, same source.
- Sanitary visit = VISIT_REASON_CODE %in% c(SNSV,SNSP,SSVF), SDWA_SITE_VISITS.csv.
- Row 3 sanitary visit restricted to same CWS-year as the MR violation (user confirmed).
- Pattern follows sanitary_visit_enforcement_lag.r (CWS-year rate table style,
  hand-assembled LaTeX, not etable()).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| CWS-year unit (not CWS-month) | User confirmed; matches "cws-year observations" wording |
| Same-year sanitary visit for row 3 | User confirmed (not "ever visited") |
| Hand-assembled LaTeX, no wrap_for_beamer() | Table has \begin{table} float; wrap_for_beamer() is only for bare-tabular etable() output per CLAUDE.md |
| Output to output/sum/ | Rate/summary table, not a regression table |

## Verification Results
- [x] Script runs end-to-end (exit 0)
- [x] Output exists at output/sum/sanitary_visit_formal_enforcement_rate.tex, non-zero
- [x] Row counts plausible and monotonically decreasing: 7,329 -> 1,018 -> 162

## Results
- All CWS-years: N=7,329, formal enforcement rate = 2.52%
- CWS-years with MR violation: N=1,018, rate = 11.59%
- CWS-years with MR violation + same-year sanitary visit: N=162, rate = 22.22%
- Direction is opposite to the substitution hypothesis: formal enforcement rate
  is HIGHER, not lower, when a sanitary visit co-occurs with an MR violation.

## Timing breakdown (added 2026-07-13, same script)
Event-level (per MR onset, N=6,523), formal enforcement = spell starting
on/after the onset date, no calendar-year restriction:
- All MR onsets: N=6,523, rate=56.54%
- Visit BEFORE onset (same year): N=225, rate=39.11%
- Visit AFTER onset (same year): N=821, rate=30.69%
Both before and after groups show LOWER formal-enforcement rates than the
unconditional 56.54% baseline -- direction is consistent with a visit
(before or after) being associated with less subsequent formal enforcement,
which is the opposite finding from the CWS-year-level row 3 (22.22% vs.
11.59% baseline). Likely explanation: the CWS-year table's baseline (all
MR-violation CWS-years, 11.59%) is a much broader/weaker-selected group than
"all MR onsets with any subsequent formal enforcement ever" (56.54% -- no
time truncation, so lifetime exposure to formal enforcement is much higher).
The two tables are not directly comparable in levels; the timing table is the
cleaner test of the substitution hypothesis since it conditions on the event
(onset) and orders the outcome to occur after it.

## Open Questions / Blockers
- Before vs. after groups are not mutually exclusive (bracketing visits count
  in both) and are both associational, not causal -- no controls for
  underlying violation severity or CWS type. Visit timing could still be
  confounded (e.g., worse CWSs get visited both before and after, and are
  also less likely to progress to formal escalation due to unobserved fixes).

## Revision (2026-07-13, later): 5-row CWS-year table
Rebuilt sanitary_visit_timing_formal_enforcement_rate.tex (still in
output/sum/, not output/reg/ per user confirmation) to have the SAME first 3
rows as sanitary_visit_formal_enforcement_rate.tex, plus two new rows using a
365-calendar-day window (not same-calendar-year) tied to the MR onset date,
with formal-enforcement outcome always measured in year t = the MR onset's
calendar year:
- Row 4 "CWS-years with an MR violation following sanitary visit": visit
  occurs in the 365 days BEFORE the MR onset (visit -> then MR violation).
  N=155, rate=17.42%.
- Row 5 "CWS-years with an MR violation preceding sanitary visit": visit
  occurs in the 365 days AFTER the MR onset (MR violation -> then visit).
  N=186, rate=24.19%.
Full 5-row table: 2.52% (all) / 11.59% (MR) / 22.22% (MR + same-year visit) /
17.42% (row 4) / 24.19% (row 5). Rows 4-5 are not mutually exclusive (a
bracketed onset could count in both); row Ns computed as unique CWS-years in
`skel` matching >=1 qualifying MR onset.

## Test script: SYR2-below-mean 6th row (2026-07-13, later)
New separate script (user chose "new script" over editing in place):
code/coal_mining_water_quality/sanitary_visit_formal_enforcement_rate_syr2_below_mean.r
-> output/sum/sanitary_visit_formal_enforcement_rate_syr2_below_mean.tex
Reproduces rows 1-5 of sanitary_visit_formal_enforcement_rate.r exactly
(verified identical Ns/rates), plus row 6: row-3 sample (MR violation +
same-year sanitary visit) further restricted to CWS-years where every SYR2
reading of arsenic/nitrate/barium/chromium/selenium that year is below that
chemical's mean. Thresholds are the fixed published means from
output/sum/6yr_huc02fe_inorg_val_sumstats_ravalli_2005.tex (user confirmed
use those exact numbers rather than recomputing): arsenic=0.0029,
nitrate=0.7520, barium=0.0748, chromium=0.0059, selenium=0.0048 mg/L.
CWS-year qualifies based on whichever of the 5 are tested that year (user
confirmed subset-OK, not all-5-required). SYR2 source:
clean_data/cws_6year_review_measurement_level_syr2.parquet.
Result: row 6 N=12, rate=8.33% (vs. row 3's 22.22% baseline on N=162) --
small N, but the only row so far showing a rate below the unconditional
formal-enforcement rate among MR-violation CWS-years (11.59%), consistent
with clean SYR2 readings alongside a sanitary visit predicting less formal
enforcement.

## Above-mean mirror script (2026-07-13, later)
New file: code/coal_mining_water_quality/sanitary_visit_formal_enforcement_rate_syr2_above_mean.r
-> output/sum/sanitary_visit_formal_enforcement_rate_syr2_above_mean.tex
Exact mirror of the below-mean script with row 6 flipped to require every
tested SYR2 chemical (of the 5) ABOVE its mean instead of below. Rows 1-5
verified identical to both prior scripts. Row 6: N=1, rate=0.00% -- the
"all 5 tested chemicals above mean" condition is rare (51 CWS-years total
satisfy it before intersecting with row 3's MR+visit sample), so this cut is
underpowered to the point of being uninformative on its own.

## Above-mean revision: any() instead of all() (2026-07-13, later)
Edited sanitary_visit_formal_enforcement_rate_syr2_above_mean.r: row 6 now
qualifies a CWS-year if ANY tested chemical (of the 5) is above its mean,
not requiring all tested chemicals to be above (previous all()-based version
had only N=1). New result: N=17, rate=5.88% (vs. row 2 baseline 11.59%,
row 3 baseline 22.22%). This is now a usable sample size and, like the
below-mean row (N=12, rate=8.33%), falls below the unconditional
MR-violation baseline -- both "below mean" and "any-above mean" cuts of the
row-3 sample show lower formal-enforcement rates than the row-2/row-3
baselines, though ns remain small (12-17).

## Next Steps
- N=12 (below-mean, all()) and N=17 (above-mean, any()) are still fairly
  small; treat as suggestive only, not reliable estimates. If pursuing
  further, consider a regression version with CWS/year FE (as in
  sanitary_visit_enforcement_iterative.r) to net out CWS-level confounds.
