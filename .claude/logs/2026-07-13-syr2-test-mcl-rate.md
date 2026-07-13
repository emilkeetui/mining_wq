# Session: 2026-07-13 — sanitary_visit_syr2_test_mcl_rate

## Objective
Build a new rate table (pattern-matched on `sanitary_visit_formal_enforcement_rate.r`)
at the CWS x SYR2-sample-date level (strictly downstream 2SLS sample), reporting
the arsenic/nitrate/IOC MR violation rate: row 1 over all sample dates, row 2
restricted to sample dates where the measurement's ratio-to-MCL > 0.5.

## Key Context
- Chemical scope confirmed via AskUserQuestion: CHEMID_name in
  {arsenic, nitrate, selenium, barium, chromium} (TARGET_CHEMS convention).
- MR outcome linkage confirmed: same calendar year as the sample date, 1 if any
  of arsenic_MR_share / nitrates_MR_share / inorganic_chemicals_MR_share > 0.
- Data: clean_data/cws_6year_review_measurement_level_syr2.parquet has a
  precomputed `ratio` column (VALUE/mcl_mgL) — no need to recompute.
- Output: output/sum/sanitary_visit_syr2_test_mcl_rate.tex (sum/, not reg/,
  since it's a rate table not a regression).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Restrict SYR2 chems to TARGET_CHEMS (5 chems) | Matches existing scripts' convention and the arsenic/nitrate/IOC MR outcome scope |
| MR linkage by calendar year of sample date | User-confirmed; matches syr2_mr_comparison.r's any_mr construction |

## Verification Results
- [ ] Script runs end-to-end
- [ ] Output exists at expected path
- [ ] Row counts plausible

## Open Questions / Blockers
- None

## Next Steps
- Write and run code/coal_mining_water_quality/sanitary_visit_syr2_test_mcl_rate.r
