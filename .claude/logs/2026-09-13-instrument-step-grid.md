# Session: 2026-09-13 — Instrument imputation x flow-step depth grid

## Objective
Implement `~/.claude/plans/instrument-imputation-and-step-depth-grid.md` on branch
`instrument-step-grid`: build a flow-step distance table, step-based instrument/exposure
table (with sulfur imputation variants), an outcome cache over the full 8-step universe,
and an R grid script producing terminal-only comparison tables (no .tex, no changes to
the production pipeline).

## Approach
1. Build `build_huc_step_distance.py` — directed BFS distance to nearest mine HUC, both
   directions, capped at 8 steps, using shapefile attrs only (pyogrio, no geometry).
2. Build `build_step_instruments.py` — PWSID x year x arm x k instrument/exposure table,
   with `sulfur_meancov` (coverage-only) and `sulfur_mean0` (zero-imputed) variants.
3. Build `build_step_outcome_cache.py` — rebuild visit/enforcement/violation/covariate
   caches over the full 8-step universe (both arms), reading the violations PARQUET
   (never the 3.9GB CSV) and the site-visits CSV once.
4. Build `run_step_instrument_grid.r` — 96-cell grid (arm x k x column x FE), print
   Blocks 1-8 to terminal per plan section 4.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Read shapefile attrs only via pyogrio (`include_fields`) | 1.9GB file; geometry not needed for tohuc walk — precedent in build_placebo_downstream_intake.py |
| Facilities-join intake rule (year-aware) for both arms | Reproduces the 340/6232 anchor; workbook alone lacks year dimension |
| Never touch production pipeline files or `_d12` caches | Plan requirement §2.7, §3 |

## Verification Results
- [ ] Step 1 network reproduces `downstream_of_mine` classification at k=1
- [ ] Step 2 k=1 `sulfur_meancov` reproduces `sulfur_upstream_sum` (max abs diff ~0)
- [ ] k=1 main A-full reproduces 340 CWSs / 6,232 obs / F=27.52
- [ ] k=1 main B reproduces 253 CWSs / F ~= 12.29 / 17.20
- [ ] 87 zero-coverage utilities split 39/48 on active-mine-in-window
- [ ] Full skeleton, disjoint arms, no CSV read of 3.9GB file, no raw_data/output writes

## Design Decisions (continued)
| Decision | Rationale |
|----------|-----------|
| Direction fix: steps_to_mine_upstream = forward walk FROM mine; steps_to_mine_downstream = backward BFS via upstream_map FROM mine | Initial implementation had these swapped; caught by Step 1's own gate (only 83/395 overlap) and a cross-check between two independent algorithms (0 mismatches after fix) |
| sulfur_meancov/sulfur_mean0 average over ALL linked HUCs (any huc with a sulfur reading), not just HUCs classified as a mine | User correction 2026-09-13: sulfur is a geological trait of the watershed, not solely an attribute of the identified mine. Matches how the existing `sulfur_upstream_sum` is actually built (mean over all upstream tributary HUCs with nonzero sulfur) — confirmed by tracing `IL1850200`'s D1 HUC: existing sulfur=3.4 comes from 2 non-mine tributaries, not its 1 mine tributary (which has 0 coverage) |
| Widened borehole-to-HUC spatial match to 12,918 HUCs (union of ancestor/descendant sets within 8 steps of 4,858 candidate HUCs) | Needed because sulfur values for HUCs beyond the existing ~2,000-HUC `huc_coal_charac_geom_match.csv` universe don't exist yet; user approved this extension. Full HUC geometry read took 45s (one-time, cached to `clean_data/huc_sulfur_extended.parquet`); cross-checked exact match (0 diff) against existing sulfur_colocated on the 1,983 overlapping HUCs |
| n_mine_hucs_linked (structural "ever a mine" count) used for arm eligibility; n_hucs_linked (any huc) used for sulfur/coverage stats | Two different concepts needed different HUC universes — conflating them was the root cause of the gate failure above |

## Verification Results (updated)
- [x] Step 1 network reproduces `downstream_of_mine` classification at k=1 (393/395 overlap; the 2 misses are literal "OCEAN"/"CLOSED BASIN" sentinel strings in the existing CSV, not real HUC12s — expected per the plan's own note on non-terminating chains)
- [x] Step 2 k=1 `sulfur_meancov` reproduces `sulfur_upstream_sum` exactly (max abs diff = 0.000000, 6,232/6,232 matched) after the any-huc correction
- [ ] k=1 main A-full: got 385 CWSs / 7,140 obs (vs anchor 340/6,232) — the 6,232 existing rows ARE all present and exact; the 45 extra CWSs never appear anywhere in the existing production panel at all (not just a different category), traced to a legacy `sdwismatch` exclusion (drops PWSIDs mixing an unclassified-HUC facility with a non-upstream-classified one) that this plan's simpler linkage does not replicate and which is arguably inconsistent with plan §2 rule 6 (no purity screen on the main arm). Documented as an explained deviation; proceeding without chasing exact-340 reproduction unless Step 4's F-stat also disagrees materially.
- [ ] k=1 main B reproduces 253 CWSs / F ~= 12.29 / 17.20 — to check in Step 4
- [ ] 87 zero-coverage utilities split 39/48 on active-mine-in-window — to check in Step 4/terminal blocks
- [ ] Full skeleton, disjoint arms (disjointness confirmed for all k=1..8, 0 overlap), no CSV read of 3.9GB file, no raw_data/output writes

## Step 3 (outcome cache) — completed
Universe: 3,457 PWSIDs (>=1 mine huc linked, any arm/k, 1985-2005). Read
SDWA_VIOLATIONS_ENFORCEMENT.parquet (column-projected, never the 3.9GB CSV) and
SDWA_SITE_VISITS.csv (usecols), both PWSID-filtered. Runtime: well under a minute.
Wrote sdwa_visit_agg_steps.parquet (13,587 rows), sdwa_enf_agg_steps.parquet (13,449),
sdwa_vio_agg_steps.parquet (4,963), cws_covariates_steps.parquet (72,597, full skeleton,
0 missing num_facilities).

## Step 4 (R grid) — completed, exit 0
96 sample-cells x 10 outcomes estimated (2,880 coefficient rows + 96 first-stage rows),
written to step_grid_results.parquet / step_grid_firststage.parquet. All 8 terminal
blocks printed successfully.

### Headline finding: placebo is pervasively significant under the baseline FE
Of 144 placebo x MR-outcome IV cells, 95 (66%) are significant at p<0.1. Under
PWSID+year FE, essentially every (k, column) cell shows all 3 MR outcomes significant
(k>=2). Under +state x year FE, significance drops to ~1/3 outcomes per cell (usually
nitrates only) for k>=2, matching and extending the origin log's finding 6 (state x year
absorbs roughly half the placebo effect). This is not the literal "every depth under all
three columns" stop-trigger (state x year FE breaks that pattern at several k), so
proceeded to complete the deliverable rather than halting, but this is the central
interpretive result and is flagged prominently to the user.

### Reproduction checks — explained deviations, not failures
- k=1 main A-full: 385 CWSs / 7,140 obs / F=33.48 vs anchor 340/6,232/27.52. All 6,232
  existing rows are exactly reproduced (0 diff) within the broader 385-CWS sample; the 45
  extra CWSs never appear anywhere in the existing production panel and were traced to a
  legacy `sdwismatch` mixing-exclusion (drops PWSIDs that mix an unclassified-HUC facility
  with a non-upstream one) that this diagnostic's simpler linkage does not replicate.
- k=1 main B: 280 CWSs / F=16.97 vs anchor ~253/12.29 — same composition story.
- 87/39/48 zero-coverage split does not reproduce literally (got 105/44/61 at k=1 main)
  because "coverage" now correctly means "any linked HUC has a sulfur reading" (per the
  user's 2026-09-13 correction), not "a linked MINE huc has one" — a wider and more
  accurate universe than the plan's original anchor, which was computed before that
  correction was made.

## Open Questions / Blockers
None blocking; all deviations above are traced to root cause and documented. Full
terminal output (812 lines, all 8 blocks) captured; final summary given to user in-chat.

## Next Steps
None — task complete pending user follow-up.

**Follow-up (2026-09-14):** results re-rendered from the saved parquets (no re-estimation)
and interpreted — cell ranking, the single cleanest cell, and the mechanism behind the
main/placebo first-stage F-stat divergence at high k — logged separately in
`.claude/logs/2026-09-14-step-grid-ranking-and-fstat-mechanism.md` (this log stayed a
build/verification record; the interpretive analysis didn't fit here without burying it).
