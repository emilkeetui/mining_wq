# Session: 2026-07-16 — Why mr_concentration_lag_national_downstream_states.tex and
# _yearly.tex coefficients differ so much

## Objective
Explain why the coefficients in `output/reg/mr_concentration_lag_national_downstream_states.tex`
and `output/reg/mr_concentration_lag_national_downstream_states_yearly.tex` look so different,
despite both being built from `clean_data/mr_concentration_lag_national_nitrate.parquet` and
restricted to the same downstream-2SLS-sample states.

## Key Finding
These are NOT two estimates of the same effect — they are structurally different regressions.
Different sign changes and magnitude differences are expected, not a bug.

## Design Differences

| Dimension | `_downstream_states.tex` (mr_concentration_lag_national_downstream_states.r) | `_yearly.tex` (mr_concentration_lag_national_downstream_states_yearly.r) |
|---|---|---|
| Unit of observation | **Reading level** (one row per SYR2 sample), N=541,483 | **CWS-year level**, N=480,015 (53,335 CWSs x 9 years, 1997-2005) |
| Key regressor timing | `near_mcl` = 1 if THIS SPECIFIC reading is 50-100% of MCL | `near_mcl_lead6/12`, `near_mcl_lag6/12` = 1 if ANY reading (not necessarily this one) fell in a 6/12-month window before/after ANY month in that CWS-year |
| Outcome definition | `mr_same_fwd`/`mr_same_fwd6mon` = MR violation in the forward window (1-365 or 1-182 days) FROM THAT SAME READING'S DATE | `mr_violation` = 1 if ANY nitrate MR violation onset occurred anywhere in that calendar year, independent of any specific reading |
| Design type | Reading-triggered forward-outcome (contemporaneous/forward) | Event-study style leads/lags, rolled up to CWS-year |
| `mean_conc_z` construction | The reading's own PWSID-year z-scored concentration, entered directly | Mean of the z-score across readings falling in the lead/lag window, rolled up to CWS-year; **zero-filled** (not NA) for CWS-years with no reading in that window |
| Sample restriction | All readings in downstream-sample states | Additionally restricted to CWS-years 1997-2005, valid `sample_dt` required |

## Resulting Coefficient Differences
- `_downstream_states.tex`: `near_mcl` coefficient is **positive** (0.0042*, 0.0015* for LPM;
  0.1568**, 0.0969 for logit) — a near-MCL reading raises MR-violation likelihood in the
  window immediately following THAT SAME reading.
- `_yearly.tex`: `near_mcl_lag6`/`lag12` (reading occurred in the past) is **negative and
  significant** (-0.0163*** to -0.0210***, -0.0062** to -0.0115***) — CWS-years following
  a near-MCL reading elsewhere in time have FEWER MR onsets. `near_mcl_lead` is also negative.

The zero-filling of `mean_conc_z_lead/lag` for no-reading CWS-years also pulls that
coefficient's scale/sign in a different direction than the reading-level version's
regressor, which has no such floor.

## Why This Isn't a Bug
The `_yearly.r` header explicitly describes it as mirroring the panel-construction style of
`syr2_test_mr_violation_bychem_iterative.r` (binary lead/lag window indicators) rather than
being a coarsened version of `_downstream_states.r`'s reading-triggered design. The two
scripts answer different questions:
- `_downstream_states.r`: "does THIS reading, if near-MCL, predict an MR violation soon after
  THIS reading?"
- `_yearly.r`: "does a CWS-year with a near-MCL reading nearby in time (before or after) have
  more/fewer MR onsets that year?"

## Open Question / Next Steps
If these two are meant to be nested/comparable versions of the same test (coarsened to
CWS-year for tractability, per the yearly script's stated motivation of national-scale
etable() being "prohibitively slow" at CWS-month grain), the regressor and outcome
definitions need to be reconciled (e.g., match the yearly script's outcome to "MR violation
following THIS reading" rather than "any MR violation that year") before comparing
coefficients as if they were testing the same specification at different levels of
aggregation.
