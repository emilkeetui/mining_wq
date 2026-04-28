# Session: 2026-04-27 — Health violation composites on 4-step downstream sample

## Objective
Implement MCL composite and health-based composite outcomes on the 4-step downstream
sample (prod_vio_sulfur_4step.parquet) and run 2SLS regressions for both.

## Changes Made

- **build_4step_sample.py**: Added `IS_HEALTH_BASED_IND` to `vio_cols`; created
  `health_based` binary from Y/N flag; added `{contaminant}_health_share` columns
  for all 10 contaminants (parallel to existing `_MCL_share`, `_MR_share`, `_TT_share`).
  Re-ran to rebuild `prod_vio_sulfur_4step.parquet` (126 cols, 46,284 rows).

- **run_4step_tables.r**: Constructs `mining_health_MCL_share_days` (sum of 4 MCL
  mining vars) and `mining_health_based_share_days` (sum of 4 health-based mining vars)
  after loading. Added regression calls for both composites in the progressive sample
  loop. Added `rm(model_list, result); gc()` after each etable call to prevent
  memory exhaustion.

- **run_4step_d4_composites.r** (new): Standalone script running D1–D4 composite
  tables only, in a fresh R session — needed because the full script segfaults on
  the D1+D4 sample after ~40+ sequential feols calls exhaust memory.

## Output Files (all in output/reg/)
- `2sls_4step_d{1,d1_d2,d1_d3,d1_d4}_mining_mcl_composite.tex`
- `2sls_4step_d{1,d1_d2,d1_d3,d1_d4}_mining_healthbased.tex`

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Per-contaminant health_share (not aggregate) | Mirrors existing MCL/MR/TT structure; composites built in R for flexibility |
| Separate D1+D4 script | R segfaults after ~40 sequential feols on large samples; fresh session avoids this |
| gc() after each etable | Prevents gradual memory leak across 16 sequential table writes |

## Key Results (2SLS, sum of mining-violation days)

| Sample | N | 2SLS | SE | F-stat |
|--------|---|------|----|--------|
| D1 | 8,190 | −3.86 | (2.64) | 412 |
| D1–D2 | 13,671 | −2.70 | (1.96) | 475 |
| D1–D3 | 17,976 | −2.90 | (1.84) | 482 |
| D1–D4 | 21,756 | −4.55** | (2.16) | 553 |

## Open Questions / Findings
- MCL composite = health-based composite exactly: all health-based violations for
  nitrates/arsenic/inorganic/radionuclides are MCL-category. TT=0, health-MR=0.
  Can collapse to one table in the paper.
- Reduced form is positive; 2SLS is negative. This is consistent because the first
  stage is negative (ARP reduced mines in high-sulfur areas). Direction is correct
  but worth noting for downstream sample interpretation.
- Significance only at D1–D4 — power increases as sample expands.

## Next Steps
- Consider collapsing MCL composite and health-based tables (they are identical)
- Discuss downstream RF sign in paper
