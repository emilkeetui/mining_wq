# Session: 2026-06-06 — Raw-water-only mean concentrations

## Objective
Change the 6-Year Review build so mean analyte concentrations use **raw (source)
water only**, then regenerate the downstream inorganic mean-concentration table
`output/reg/6yr_huc02fe_inorg_val.tex`.

## Changes Made
- `code/coal_mining_water_quality/cws_6year_review.py`:
  - Replaced `_reconcile_raw_finished()` (Ravalli step 6, which preferred FN samples
    when finished mean < raw mean) with `_use_raw_only()`: drops every explicitly
    finished-water (`FN`) sample before collapsing; keeps `RW` and unlabeled rows.
  - Updated header comment (step 6 description), `collapse_to_pwsid_year` docstring,
    and entry-point comment.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Drop FN, keep RW + unlabeled | SYR2 (1998–2005) has no SOURCE_TYPE; strict RW-only would delete the entire main-sample era. User chose to keep unlabeled rows. |
| Asymmetry removed | Old logic blended raw+finished unless finished was lower; new logic always excludes treated water so the mean reflects the source-water pollution signal. |

## Verification Results
- [x] cws_6year_review.py runs end-to-end (exit 0)
  - Raw-water restriction: dropped 3,441,978 FN rows; kept 2,559,198 raw/unlabeled
  - Collapsed: 875,061 PWSID×chem×year rows
  - Merged: 484,660 rows × 235 cols written to cws_6year_review_cleaned.parquet
- [x] cws_6year_review_huc02fe.r re-run (exit 0); 6yr_huc02fe_inorg_val.tex regenerated
  - Coal-prod coefficient on mean concentration (10M ST), raw water:
    arsenic -0.0002* (0.0001); nitrate 0.0330 (0.0504); barium 0.0109** (0.0044);
    chromium -4.39e-05 (0.0002); selenium -0.0001 (0.0001).
  - Rscript path correction: use `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`
    (the verification-protocol path `Z:/R/...` does not exist on this machine).

## Result
Switching to raw water leaves the inorg mean-concentration story essentially
unchanged: only barium (+, 1%) and arsenic (−, 10%) significant; nitrate,
chromium, selenium null.
