# Session: 2026-09-15 — A2 intake-purity sample pipeline

## Objective
Replace the "at least one qualifying intake" (`n_mine_hucs_linked >= 1`) sample
definition with the A2 (downstream-only for main; mirror upstream-only for placebo)
purity screen across the k2 main arm and the k=1..8 comparison grid, per plan
`a2-intake-purity-sample-pipeline.md`. Regenerate the 14 `_k2` `.tex` and 2 `_k2`
`.png` published outputs in place; no `main.tex` edits.

## Approach
1. New `build_step_purity_flags.py`: classify every candidate utility's intake HUC
   portfolio at k=1..8 (single arm-agnostic classify function per HUC: downstream >
   upstream > unclassified, matching static CSV priority), emit `(PWSID, arm, k,
   n_intake_hucs, n_down, n_up, n_uncl, a2_pure)` to
   `clean_data/cws_data/step_purity_flags.parquet`.
2. `k2_common.r` gains `apply_a2()` helper and `build_k2_panel(a2_only = TRUE)` default.
3. Update inline arm/k filter sites (run_kgrid_coefs.r, run_step_instrument_grid.r,
   run_kgrid_syr2_coefs.r, run_k2_6yr_tables.r, run_step_top3_outcomes.r,
   run_mr_concentration_lag_ols_k2.r, build_step_huc_links_k2.py) to join a2_pure.
4. Re-anchor every hard-coded gate after verifying the new value (never loosen
   blindly). `compare_k2_intake_purity.r` keeps `a2_only = FALSE` and stays runnable
   as the SQ-vs-A2 robustness reference.
5. `build_step_visit_enf_k2.py` / `build_step_visit_enf_kgrid.py` are NOT rerun —
   restrict-only caches remain valid supersets under the shrinking A2 universe
   (asserted in verification, not assumed). `build_step_huc_links_k2.py` IS rerun
   (feeds the scatter figure).

## Key Context
- k=2 A2 anchors verified earlier this session by `compare_k2_intake_purity.r`:
  582 utilities, 10,641 obs, F 49.10, MR IV nitrates 3.94/1.75, arsenic 3.78/1.56,
  inorganic 3.06/1.66.
- Probe table (read-only, plan) gives A2 counts at every k=1..8 for both arms; these
  are the hard assertion targets for `build_step_purity_flags.py`.
- Branch: `k2-intake-purity`. Prior task's work (`build_k2_intake_purity.py`,
  `compare_k2_intake_purity.r`) already present, uncommitted at session start.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Single classify() per (huc12, k), reused for both arms | main a2_pure = all-downstream, placebo a2_pure = all-upstream; same underlying geography property, cheaper than per-arm intake_link restriction |
| Skip rebuilding visit/enf kgrid+k2 caches | Restrict-only aggregation, A2 universe is a strict subset at every k — existing supersets remain valid, verified by assertion instead |

## Verification Results
- [x] `build_step_purity_flags.py` reproduces the probe table exactly at every k=1..8,
      both arms (16/16 OK); nesting, disjointness, and candidate-huc no-op invariant
      gates all passed.
- [x] k=2 A2 early gate (`run_k2_main_tables.r`) reproduced the 6 independently
      verified numbers exactly: 582 utilities, 10,641 obs (state x year FE columns),
      F 49.10, MR IV nitrates 3.94/1.75, arsenic 3.78/1.56, inorganic 3.06/1.66.
- [x] Full execution order ran end-to-end, zero errors: `build_step_purity_flags.py`
      -> `run_k2_main_tables.r` -> `run_k2_placebo_tables.r` -> `run_step_instrument_grid.r`
      -> `run_kgrid_coefs.r` -> `run_kgrid_syr2_coefs.r` -> `run_k2_6yr_tables.r` ->
      `run_k2_sum_tables.r` -> `run_step_top3_outcomes.r` ->
      `run_mr_concentration_lag_ols_k2.r` -> `build_step_huc_links_k2.py` ->
      `run_k2_figures.r` -> `compare_k2_intake_purity.r` (a2_only=FALSE check).
- [x] All re-anchored gates pass (see table below).
- [x] `main.tex` recompiles (85 pages, exit 0), zero `??` refs, all 19 `_k2`
      `\outreg`/`\outsum`/`\outfig` appendix items render (the plan undercounted —
      4 `\outsum` + 14 `\outreg` + 2 `\outfig` = 20 items using `_k2`, including
      `mr_concentration_lag_ols_k2` which the "14/2" count in the plan missed).
- [x] Cache-superset claim verified by assertion, not assumed: every A2 PWSID (any
      arm/k) is in the kgrid visit/enf cache universe; every A2 k=2 PWSID is in the
      k2 visit/enf cache universe. `build_step_visit_enf_k2.py` /
      `build_step_visit_enf_kgrid.py` correctly left unrun.
- [x] `compare_k2_intake_purity.r` (a2_only=FALSE) still reproduces every published
      status-quo anchor exactly (SQ=666, A1=656, A2=582; first-stage F 50.01; MR IV
      3.28/1.73, 3.11/1.52, 2.00/1.60; SYR2 OLS all 4 chemicals) — SQ-vs-A2
      robustness comparison stays intact.
- [x] Placebo falsification test remains null under A2: k=2 state x year FE MR
      p-values are .21/.46/.33 (all > 0.1), slightly *more* comfortably null than
      the pre-A2 .17/.42/.26. No "stop and report" trigger.

## Re-anchored constants (old -> new, A2 k=2 unless noted)
| File | Anchor | Old | New |
|---|---|---|---|
| `run_k2_main_tables.r` | Utilities / obs (state x yr FE) | 666 / — | 582 / 10,641 |
| `run_k2_main_tables.r` | First-stage F | 50.01 | 49.10 |
| `run_k2_main_tables.r` | MR IV nitrates est/se | 3.28/1.73 | 3.94/1.75 |
| `run_k2_main_tables.r` | MR IV arsenic est/se | 3.11/1.52 | 3.78/1.56 |
| `run_k2_main_tables.r` | MR IV inorganic est/se | 2.00/1.60 | 3.06/1.66 |
| `run_k2_placebo_tables.r` | Placebo first-stage F | 53.17 | 53.53 |
| `run_k2_placebo_tables.r` | Placebo MR p-values (nit/ars/ioc) | .17/.42/.26 | .21/.46/.33 |
| `run_kgrid_coefs.r` gate 3 | main any_tech/any_smpl/any_insp/no_enf | -0.10/0.08/2.10/0.68 | 0.67/0.48/2.13/-0.42 |
| `run_kgrid_coefs.r` gate 3 | placebo any_tech/any_smpl/any_insp/no_enf | 1.81/2.52/3.03/1.23 | 0.85/1.58/2.62/2.81 |
| `run_kgrid_syr2_coefs.r` gate 1 | k=1 main SYR2 anchor | 0.0023/0.0572/0.0171/0.0033 | unchanged (exact match, as predicted) |
| `run_step_top3_outcomes.r` | k=1 huc02^yr anchor note | "exact equality not expected" | now an exact match; note rewritten |
| `run_step_instrument_grid.r` / `render_step_instrument_grid.r` | k=1 main A-full CWS-count note | "45 extra CWSs (385 vs 340)" | 0 extra (340 = 340); note rewritten, residual obs/F gap (6242 vs 6232, F 31.88 vs ~27.52) attributed to linkage-simplicity, not PWSID divergence |

## Per-k A2 sample sizes (utilities)
| k | main | placebo |
|---|------|---------|
| 1 | 340 | 370 |
| 2 | 582 | 607 |
| 3 | 764 | 784 |
| 4 | 925 | 969 |
| 5 | 1088 | 1166 |
| 6 | 1216 | 1365 |
| 7 | 1342 | 1521 |
| 8 | 1426 | 1646 |

## Open Questions / Blockers
- None. All gates pass; placebo stays null; SQ baseline stays reproducible.

## Next Steps
- Nothing committed per user instruction ("Nothing is committed until you ask").
  Ready for `git status` review and commit/PR when the user asks.
