# Session: 2026-06-23 — MR violation concentration lag

## Objective
Execute plan `mr-violation-concentration-lag.md`: test whether MR violations
follow high contaminant readings 6-12 months later (regulator-pivot mechanism),
on the downstream-only mining sample, SYR2 only.

## Changes Made
- `code/coal_mining_water_quality/cws_6year_review_measurement_dates.py`: new.
  SYR2-only, measurement-level (sample_date preserved), Ravalli MDL/sqrt(2) +
  EPA method-MDL fallback (Step 1.5b), downstream-only PWSID filter applied
  immediately after each chemical read.
  Output: `clean_data/cws_6year_review_measurement_level_syr2.parquet` (1,832 rows).
- `code/coal_mining_water_quality/build_mr_concentration_lag.py`: new. Matches
  each measurement to forward (6-12mo) and past-placebo (6-12mo prior) MR
  violations, same-contaminant and any-IOC.
  Output: `clean_data/mr_concentration_lag_measurement.parquet` (1,832 rows).
- `code/coal_mining_water_quality/mr_concentration_lag.r`: new. LPM via
  `fixest::feols`, FE = PWSID + YEAR (+ contaminant_code for pooled), cluster ~PWSID.
  Output: `output/reg/mr_concentration_lag.tex`, `output/reg/mr_concentration_lag_placebo.tex`.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Arsenic column omitted from both tables | Arsenic detect rate in the downstream-only SYR2 sample is 6.6% — below the >10% Ravalli filter — so zero arsenic rows survive Step 1. Fitting `feols` on 0 rows is impossible; faking a column would misrepresent the result. |
| `np.datetime64()` cast before `searchsorted` | This numpy/pandas combination raises `TypeError: '<' not supported between int and Timestamp` when passing a raw `pd.Timestamp` to `ndarray.searchsorted`; casting to `np.datetime64` fixed it. |
| EPA method-MDL fallback dict values flagged as approximate | No exact published EPA method MDLs were available in-repo; used representative values from EPA Method 200.8/300.0/245.1/335.4 validation studies, documented in-code as approximate. Affects only int the non-detect imputation for records with missing/unreliable record-specific LODs (2,067 of 1,832 final rows' source records). |

## Verification Results
- [x] Both Python scripts exit 0; both parquets exist
- [x] PWSID str, YEAR int64, sample_date datetime64 in both parquets
- [x] Downstream-only PWSID set (349 unique) and SYR2 years (1998-2005) only
- [x] No outcome column all-zero
- [x] R script exits 0; both `.tex` files exist, non-zero, correctly labeled (Nitrate, Pooled inorganic), N reported
- [ ] Arsenic spec (A) — not estimable: 0 surviving rows (flagged, not a failure to fix)
- [ ] Nitrate near_mcl event count is thin (3 raw near-MCL nitrate readings pre-singleton-drop) — coefficient reported but flagged as fragile

## Open Questions / Blockers
- Surviving chemicals (barium, fluoride, nitrate) differ from the plan's anticipated
  set (arsenic, barium, chromium, selenium, nitrate, nitrite) — the downstream-only
  restriction has much lower per-chemical detection rates than Ravalli's national sample.
- Mechanical-monitoring-increase vs. strategic-avoidance interpretations remain
  un-separated by this design (per plan's caveat).

## Next Steps
- None planned; report delivered to user this session.

## Update 2026-06-23 — Re-run after Step 1 change
- Step 1 (`cws_6year_review_measurement_dates.py`) was updated; re-ran Step 2
  (`build_mr_concentration_lag.py`) and Step 3 (`mr_concentration_lag.r`).
- Sample grew from 1,832 to 3,705 measurement rows; arsenic detect rate now clears
  the >10% filter (N=454 forward / N=419 placebo) — previously 0.
- `mr_concentration_lag.r` had hard-coded "Arsenic omitted (N=0)" in both `etable()`
  notes and excluded `ars`/`ars_p` from the table calls, which became factually wrong
  once arsenic started surviving. Fixed: `have_ars` now conditionally adds the Arsenic
  column/model to both tables and rewrites the note text dynamically. Re-ran; both
  `.tex` files now show Arsenic, Nitrate, Pooled inorganic columns.

## Update 2026-06-23 (2) — Spec changes per user request, NOT yet re-run
Edited `build_mr_concentration_lag.py` and `mr_concentration_lag.r` only; pipeline was
not re-executed (explicit user instruction).
- `mr_same_fwd` window widened from (s+182d, s+365d] to [s+1d, s+365d] (1-365 days after
  the measurement, both ends inclusive). `mr_anyioc_fwd`'s window is unchanged (182-365
  days) since the user only specified the same-contaminant outcome; the past-placebo
  windows (`mr_same_past`, `mr_anyioc_past`) are also unchanged. This makes the
  forward windows for same-contaminant vs. pooled-IOC asymmetric -- flagged in the new
  table notes.
- `mr_anyioc` redefined from the 14-code `IOC_CODES` `CONTAMINANT_CODE` set to
  `RULE_CODE == 333.0` (Inorganic Chemicals / Other IOC) -- the exact rule code used to
  build `inorganic_chemicals` in `sdwismatch_pwsid_level_share_yr_in_violation.py` /
  `didhet.r`, which feeds `2sls_dwnstrm_minevio_allcat_ivsum.tex`. By construction this
  now excludes arsenic (RULE_CODE 332.0) and nitrate (RULE_CODE 331.0), which have their
  own separate rule codes -- confirmed via `SDWA_REF_CODE_VALUES.csv`. Table notes in
  `mr_concentration_lag.r` updated to state this exclusion explicitly.
- `build_date_indexes()` / `attach_mr_flags()` renamed `pwsid_any_dates` ->
  `pwsid_rule333_dates`; `load_violations()` now also reads `RULE_CODE`.

### Next Steps
- Re-run Step 2 (`build_mr_concentration_lag.py`) and Step 3 (`mr_concentration_lag.r`)
  when the user is ready; row counts, detection-rate filtering, and the
  `mr_anyioc`/`mr_same_fwd` outcome means will all change and need re-verification.

## Update 2026-06-23 (3) — All windows unified to 1-365 days, NOT yet re-run
Per user instruction: "widen all windows for mr_* to [s+1d, s+365d]. Leave outcome
identical across same PWSID-same-date rows." Edited `build_mr_concentration_lag.py`
and `mr_concentration_lag.r` only; pipeline still not re-executed.
- Collapsed the separate SAME_FWD/FWD constants back into one pair: `FWD_LOW_D,
  FWD_HIGH_D = 1, 365` (now identical for `mr_same_fwd` and `mr_anyioc_fwd`, both ends
  inclusive). Mirrored the past-placebo window to match: `PAST_LOW_D, PAST_HIGH_D =
  365, 1` i.e. [s-365d, s-1d], both ends inclusive (previously 182-365 days before,
  excluding the 0-181 day band). This is an assumption -- the user said "widen all
  windows... to [s+1d, s+365d]" referring to the forward direction; mirrored it for the
  past window since the placebo's purpose is to test the same threshold in the opposite
  direction.
- Left `pool_df`/`fml_pool` unchanged: pooled regression still uses every measurement
  row (all chemicals) with `mr_anyioc_fwd`/`mr_anyioc_past` as outcome, FE on
  `contaminant_code` -- outcome is intentionally identical across same-PWSID-same-date
  rows since it no longer depends on which contaminant was measured (confirmed
  acceptable, no change requested).
- Updated `mr_concentration_lag.r` header + both `etable()` notes to drop "6-12 months"
  language and describe the unified 1-365 day forward/placebo windows.

### Next Steps
- Re-run Step 2 and Step 3 when ready.

## Update 2026-06-23 (4) — Re-run with unified 1-365 windows + RULE_CODE 333.0 mr_anyioc
Re-ran Step 2 and Step 3 with the spec from Update (3). Both exited 0; both `.tex`
outputs regenerated (`output/reg/mr_concentration_lag.tex`,
`output/reg/mr_concentration_lag_placebo.tex`).
- Row count unchanged at 3,705 (Step 2 doesn't change row count, only outcome defs).
- Forward-window results: Nitrate `ratio` coefficient on `mr_same_fwd` = 0.120
  (p=0.29, ns); `near_mcl` = 0.589 (p=0.019, *). Pooled any-IOC (RULE_CODE 333.0)
  `ratio` = -0.060 (ns), `near_mcl` = 0.004 (ns). Arsenic `ratio` = 0.109 (ns).
- Past-placebo window: Nitrate `near_mcl` flips sign and is significant
  (-0.216, p=0.046) — placebo failure for near_mcl on nitrate; `ratio` placebo
  coefficients are all insignificant and near zero as expected.
- Pooled any-IOC now excludes arsenic/nitrate by construction (RULE_CODE 333.0
  is distinct from arsenic's 332.0 and nitrate's 331.0) — pooled N=3,705 still
  includes all chemicals as rows but the *outcome* mr_anyioc only reflects
  RULE_CODE-333 MR violations, so arsenic/nitrate rows contribute FE absorption,
  not outcome signal.

### Next Steps
- None pending; re-run delivered to user this session.
