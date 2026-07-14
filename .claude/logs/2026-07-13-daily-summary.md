# Daily Summary — 2026-07-13

Sanitary-visit / enforcement-substitution thread: does a sanitary visit
substitute away from formal enforcement after an MR violation, and does SYR2
contaminant proximity to the MCL change that?

---

## 1. `sanitary_visit_formal_enforcement_rate.tex` (output/sum/)
**Script:** `sanitary_visit_formal_enforcement_rate.r`
3-row CWS-year rate table, strictly-downstream 2SLS sample (349 CWSs, 1985-2005).

| Row | Sample | N | Rate |
|---|---|---|---|
| 1 | All CWS-years | 7,329 | 2.52% |
| 2 | + MR violation | 1,018 | 11.59% |
| 3 | + MR violation & same-year sanitary visit | 162 | 22.22% |

**Finding:** direction is opposite the substitution hypothesis — enforcement rate
is *higher*, not lower, when a visit co-occurs with an MR violation.

Event-level timing check (not in this .tex, logged only): of 6,523 MR onsets,
unconditional formal-enforcement rate = 56.54%; visit-before-onset (same yr)
N=225 rate=39.11%; visit-after-onset N=821 rate=30.69% — both *below* baseline,
opposite sign from the CWS-year table (levels not comparable; different
conditioning).

## 2. `sanitary_visit_timing_formal_enforcement_rate.tex` (output/sum/)
Same script family — 5-row version adding 365-day-window timing rows to rows 1-3 above:

| Row | Sample | N | Rate |
|---|---|---|---|
| 4 | MR violation following a sanitary visit (visit in 365d before onset) | 155 | 17.42% |
| 5 | MR violation preceding a sanitary visit (visit in 365d after onset) | 186 | 24.19% |

Rows 4-5 not mutually exclusive; year t = MR onset's calendar year for the outcome.

## 3. `sanitary_visit_formal_enforcement_rate_syr2_below_mean.tex` (output/sum/, test script)
**Script:** `sanitary_visit_formal_enforcement_rate_syr2_below_mean.r`
Rows 1-5 identical to above, plus:

| Row 6 | Row-3 sample (MR + same-yr visit) restricted to CWS-years where every tested SYR2 chem (of arsenic/nitrate/barium/chromium/selenium) is below its published mean | N=12 | 8.33% |

Thresholds used (from `6yr_huc02fe_inorg_val_sumstats_ravalli_2005`): arsenic
0.0029, nitrate 0.7520, barium 0.0748, chromium 0.0059, selenium 0.0048 mg/L.
Only row so far below the MR-violation baseline (11.59%) — small N, suggestive only.

## 4. `sanitary_visit_formal_enforcement_rate_syr2_above_mean.tex` (output/sum/, test script)
**Script:** `sanitary_visit_formal_enforcement_rate_syr2_above_mean.r`
Mirror of #3, row 6 flipped to "any tested chemical above its mean" (after
revising from an `all()` version that gave only N=1):

| Row 6 (any-above) | N=17 | 5.88% |

Also below both baselines (11.59% / 22.22%) — small N, suggestive only.

## 5. `sanitary_visit_syr2_test_mcl_rate.tex` (output/sum/)
**Script:** `sanitary_visit_syr2_test_mcl_rate.r`
CWS x SYR2-sample-date level, arsenic/nitrate/IOC MR violation rate by proximity to MCL:

| Row | Sample | N | Rate |
|---|---|---|---|
| 1 | All SYR2 sample dates | 2,635 | 3.95% |
| 2 | Sample dates with ratio-to-MCL > 50% | 3 | 33.33% |

N=3 for row 2 — essentially uninformative, flagged as such.

## 6. `sanitary_visit_enforcement_type_iterative.tex` (output/reg/)
**Script:** `sanitary_visit_enforcement_type_iterative.r`
Regression version (CWS + year-month FE) splitting enforcement outcome into
formal / informal / none, on sanitary-visit lead/lag windows (±6 months),
prior violation count, and last max concentration (% of MCL).
N=87,948 (no-FE columns), N=6,743 (FE + SYR2-restricted columns).
Visit lead/lag positively predicts formal and informal enforcement and
negatively predicts "no enforcement" in the no-FE columns; effects attenuate
and lose significance once CWS/year-month FE and controls are added.

## 7. `sanitary_visit_syr2_enforcement_zscore_combined.tex` (output/reg/)
**Script:** `sanitary_visit_syr2_enforcement_zscore_combined.r`
Collapsed version of the 20-regressor iterative z-score table: SYR2 test
lead/lag (OR'd across the 5 chemicals) plus max/mean tested-value z-score,
regressed on enforcement-visit and sanitary-visit outcomes (with/without
CWS + calendar-month FE). N=11,808 (123 CWSs with >=1 SYR2 measurement,
1998-2005).
**Notable:** SYR2 test lead/lag positively and significantly predicts a
sanitary visit in columns (4)-(6) (e.g. lag coefficient 0.0118***, FE
column); max tested z-score negatively predicts sanitary visit (-0.0189***,
no-FE) and enforcement visit (-0.0033**, FE column) — higher contaminant
levels associate with *fewer* enforcement/sanitary visits, not more.

## 8. `sanitary_visit_syr2_enforcement_zscore_iterative.tex` (output/reg/, pre-existing, untouched today)
Full 20-regressor per-chemical version that #7 collapses — left in place per
user request ("test code", original untouched).

## 9. `monitoring_retesting_hazard.tex` (output/reg/) — pending, uncommitted edit
**Script:** `monitoring_retesting_hazard.r`
Continuation of 07-12 edit: table trimmed to 3 columns (LPM no-FE, LPM CWS
FE, Logit CWS FE); hazard columns 4-6 dropped from the table (models still
computed in-script). `mean_level_z` construction fixed to cumulative-mean-of-
raw-values then z-scored (not mean-of-z-scores) — coefficients shifted
modestly (e.g. col 1: 0.0610→0.0571), signs/significance unchanged.
**Not yet committed** — still showing in `git status` as modified.

---

## Open items to revisit
- Rows 6 in the above/below-mean tables (#3, #4) have small N (12, 17) —
  suggestive only; consider a CWS/year-FE regression version to firm up.
- Row 2 of `sanitary_visit_syr2_test_mcl_rate.tex` (N=3) is not really usable.
- Decide whether to prune unused hazard model code (m4-m6) in
  `monitoring_retesting_hazard.r` now that the table only shows cols 1-3.
- `monitoring_retesting_hazard.r`/`.tex` changes are uncommitted — commit
  when satisfied.
