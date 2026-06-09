# Session: 2026-06-06 — Ravalli et al. LOD cleaning for 6-year-review chemicals

## Objective
Implement Ravalli et al. (2022) appendix data-cleaning (pp. 3–5) into
`cws_6year_review.py` for the inorganic chemicals, on the full national panel
(before the downstream-CWS subset, which happens later in the R regression).

## Decisions (user)
- Detection-rate filter: make it a PARAMETER (`DETECT_RATE_MIN=0.10`, set 0 to keep all).
  At 0.10 this drops cadmium + mercury (~1.5% detection in Ravalli).
- SYR2 non-detects: EPA-method-MDL fallback (SYR2 .mdb has no record-specific LOD column).
- Write to NEW paths (`*_cleaned.parquet`); leave original outputs intact for diffing.

## Key raw-data facts
- SYR3 .txt has: System Type (C=CWS), Detection Limit Value/Unit, Detect 0/1,
  Source Type Code (FN=finished, RW=raw), Value, Unit.
- SYR2 .mdb has only PWSTYPE, DETECT, VALUE, UNITS — NO LOD col, NO raw/finished col.
- Non-detect SYR3 rows: Value NaN AND Unit NaN → imputation must also set UNITS.

## Cleaning steps implemented (order)
restrict_to_cws → normalize_units(mg/L, pCi/L) → impute_below_lod (LOD/√2;
record-specific if reported in mg/L|µg/L and ≤5µg/L, else EPA/derived MDL/√2)
→ assign_mcl_and_above → drop_gross_outliers (>100×MCL) → report_detection_rates
(drop < DETECT_RATE_MIN) → collapse_to_pwsid_year (with raw/finished reconciliation).

MDL fallback is data-derived (median reliable record-specific LOD per chemical;
`_EPA_MDL` dict left empty for official-value overrides).

## Verification Results
- [x] Script runs end-to-end (exit 0)
- [x] Outputs: cws_6year_review_chemicals_cleaned.parquet (1,216,312 rows),
      cws_6year_review_cleaned.parquet (484,660 rows). Originals untouched.
- [x] CWS restriction dropped 3.98M/17.1M rows; gross-outlier drop 44,193;
      raw/finished reconciliation 4,872 groups; detection filter dropped 17 chems.
- [x] Old vs new metal means (LOD imputation pulls means down, as expected):
      arsenic .00518->.00306, chromium .00853->.00220, nitrate 1.40->.98,
      barium .104->.062, selenium .00597->.00346.
- [x] At DETECT_RATE_MIN=0.10, cadmium (1.8%) and mercury (1.6%) DROPPED —
      they vanish from the cleaned panel. Set DETECT_RATE_MIN=0.0 to keep them.

## Bugs fixed during run
- cp1252 console can't encode U+2192 (->) — replaced unicode arrows/x in prints.
- _reconcile_raw_finished: .astype("string").eq() gives nullable bool; ~to_numpy()
  became object -1s. Fixed with .fillna(False).to_numpy(dtype=bool).

## Note: radionuclides
- alpha/beta/radium have mixed mg/L vs pCi/L records within some CWS-years;
  collapse drops 13,906 mixed-unit groups (88,845 rows). Pre-existing behavior.

## Open Questions
- Replace derived MDL medians with official EPA method MDLs?
- Confirm cadmium/mercury drop at 0.10 threshold is desired for the table rebuild.
