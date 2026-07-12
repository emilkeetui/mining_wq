# Session: 2026-07-11 — SYR2 test-occurrence version of visit-timing table

## Objective
Create `sanitary_visit_syr2_test_iterative.r` / `.tex`: a variant of
`sanitary_visit_mr_violation_iterative.r` where the outcome is whether a SYR2
test occurred at the CWS that month (instead of MR violation onset), RHS =
same 5 visit-group ±6-month window indicators.

## Key Decisions
- Sample: downstream CWSs with >=1 SYR2 measurement ever, CWS-months in the
  SYR2 window 1998-01 to 2005-12 (mirrors original spec-3 restriction).
- 2 specs only: (1) visit windows, no FE; (2) + n_prior_violations + CWS/month
  FE. Dropped pct_mcl_last_max control (circular for this outcome).

## Verification Results
- [x] Script runs end-to-end (exit 0)
- [x] Output exists: output/reg/sanitary_visit_syr2_test_iterative.tex, non-zero
- [x] Row counts plausible: 123 has-SYR2 downstream CWSs x 96 months = 11,808
      CWS-months; test_occurred mean 0.0854; N in table footnote matches.

## Next Steps
- None pending; task complete.
