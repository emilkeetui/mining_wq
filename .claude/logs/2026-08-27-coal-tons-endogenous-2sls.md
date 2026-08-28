# Session: 2026-08-27 — coal-tons-endogenous-2sls

## Objective
Reproduce six existing regression tables with `production_short_tons_coal_upstream_sum`
(scaled to millions of short tons) as the endogenous variable instead of
`num_coal_mines_upstream_sum`, keeping instruments unchanged. New files only, nothing
existing overwritten. Plan: `~/.claude/plans/coal-tons-endogenous-2sls-tables.md`.

## Approach
- New script `run_main_tables_coaltons.r` (trimmed copy of `run_main_tables.r`) produces
  the four `ivsum`->`ivsumcoaltons` tables (1 first-stage + 3 binvio 2SLS).
- New script `enforcement_chain_d12_coaltons.r` reads cached SDWA aggregates
  (`sdwa_visit_agg_d12.parquet`, `sdwa_enf_agg_d12.parquet`) instead of the 355MB/3.7GB
  raw CSVs, reproduces H2b and H3(D1) tables with the coal-tons endogenous var.
- Endogenous var scaled: `production_short_tons_coal_upstream_sum / 1e6`.
- Instruments unchanged: `post95:sulfur_unified_sum` (run_main_tables scripts),
  `post95:sulfur_unified_mean` (enforcement_chain scripts).

## Key context confirmed before starting
- Inputs verified present: `clean_data/cws_data/prod_vio_sulfur.parquet`,
  `clean_data/cws_data/sdwa_visit_agg_d12.parquet`,
  `clean_data/cws_data/sdwa_enf_agg_d12.parquet`.
- Target output filenames do not collide with existing files in `output/reg/`.
- Branch `coal-tons-2sls` created off `jmp-formatting`.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Scale endogenous var to millions of short tons | Raw tons give unreadable 1e-8 coefficients (plan decision 1) |
| Two new standalone scripts, do not edit originals | Avoid overwriting mines-based tables or bloating shared scripts |
| Enforcement tables read caches only, never raw SDWA CSVs | 355MB/3.7GB reads unnecessary; caches already cover the needed PWSIDs |
| Enforcement table names get `_ivsumcoaltons` suffix appended | No `ivsum` token in original names to substitute (plan decision 6) |

## Verification Results
- [x] Script runs end-to-end (both scripts, exit 0)
- [x] Output exists at expected path (6 files, all non-empty)
- [x] Row counts plausible / gate `nrow(panel_d1) == 6232` passed exactly
- [x] First-stage F > 10 in all tables (14.41 for ivsum scripts, 11.66 for enforcement scripts —
      matches plan's pre-computed values exactly)
- [x] Table notes conform to table-notes-conventions.md (all 6 checked manually)
- [x] Six pre-existing source tables unmodified (`git status output/reg/` shows only the
      6 new untracked coaltons files)

## Results Summary
| Table | N | F (1st stage) | 2SLS sign/magnitude (headline outcome) |
|---|---|---|---|
| fs_dwnstrm_minevio_ivsumcoaltons | 6,225 | 14.41 | coef -0.0887 (se 0.0234), matches plan spec |
| 2sls_..._allcat_ivsumcoaltons_binvio | 6,225 | 14.41 | inorganic_chemicals_bin: 0.172* (positive, as expected for mining outcome) |
| 2sls_..._mcl_ivsumcoaltons_binvio | 6,225 | 14.41 | small/insignificant (MCL violations rare in binary form) |
| 2sls_..._mr_ivsumcoaltons_binvio | 6,225 | 14.41 | inorganic_chemicals_MR_bin: 0.192* (positive) |
| h2_snsv_d12_ivsumcoaltons | 6,225 | 11.66 | any_snsv: 0.461** (positive) |
| h3_inf_formal_d12_ivsumcoaltons | 6,225 | 11.66 | any_formal: -0.185** (2SLS); RF positive (0.0145***) — consistent given negative first stage (RF = FS x IV) |

Quality gate: ~90 (peer-review ready) — runs cleanly, header blocks present, cross-language
schema not applicable (R-only), notes pass all 9 table-notes-conventions.md rules, F-stats
match plan's pre-verified values exactly, no existing files touched.

Naming assumption (plan decision 6): enforcement tables named with `_ivsumcoaltons` suffix
appended since their original names had no `ivsum` token to substitute. Flagged to user.

## Open Questions / Blockers
- None. Task complete.

## Next Steps
- None outstanding. Out-of-scope items (writeup mirroring, main.tex \input, surface-water
  variants) intentionally not done per plan decision 7.
