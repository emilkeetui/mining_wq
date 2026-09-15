# Session: 2026-09-15 — kgrid-coef-plots

## Objective
Produce coefficient-vs-k figures (k = 1..8 flow steps upstream/downstream) for the full k2 outcome
set (MR, MCL, visit-type, enforcement-type), with ±1 SE error bars, per plan
`kgrid-coefficient-plots-by-flow-steps.md`.

## Changes Made
- `code/coal_mining_water_quality/build_step_visit_enf_kgrid.py`: new full-universe (3,457 PWSID)
  visit/enforcement cache (`sdwa_visit_agg_kgrid.parquet` 13,587 rows, `sdwa_enf_agg_kgrid.parquet`
  13,449 rows). Both consistency gates (vs `_steps`, vs `_k2` subset) passed with 0 mismatches.
- `code/coal_mining_water_quality/run_kgrid_coefs.r`: new k=1..8 x 2-arm x 14-outcome x 3-model
  (672 regressions) estimator. Writes `kgrid_coefs.parquet` (672 rows) and
  `kgrid_firststage.parquet` (16 rows). All 4 in-script gates passed exactly (0 diff vs
  `step_grid_results.parquet`/`step_grid_firststage.parquet` for 10 shared outcomes/16 k-arm
  first stages; k=2 anchors from h2/h3 .tex matched to 2 decimals for the 4 new outcomes;
  no NA coefficients).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Branch `kgrid-coef-plots` off `instrument-step-grid` | plan pre-flight step 1 |
| libgomp "Thread creation failed" transient warning on first R run, exit 0 on retry | not a code bug; system resource contention during fixest's parallel fitting -- re-run succeeded cleanly |

- `code/coal_mining_water_quality/plot_kgrid_coefs.r`: new figure script, reads only the Step-2
  parquets (no re-estimation). Produces `kgrid_{mr,mcl,visit,enf}_coefs.png` (3x2 facet_grid:
  model x arm, dodge points+bars, Okabe-Ito colours, decimal accuracy chosen per figure from
  y-span) and `kgrid_first_stage.png` (patchwork: FS coefficient panel + clustered-F panel with
  F=10 reference line).

## Verification Results
- [x] Step 1 (Python cache) runs end-to-end, gates pass
- [x] Step 2 (R k-grid regressions) runs end-to-end, gates pass
- [x] Step 3 (R figures) runs end-to-end, 5 PNGs produced and visually verified

## Open Questions / Blockers
-

## Next Steps
- Awaiting user review of the 5 figures before committing (per plan step 5, verification item 5).
- Quality score: ~90 (peer-review ready) -- all verification gates passed exactly, formatting
  rules (no sci notation, capitalized labels, decimal-aligned axes, consistent per-figure
  accuracy, no "placebo" wording, legend/strip labels complete) checked by visual inspection of
  all 5 PNGs. Not scored 95: annotation placement for "F = 10" needed one manual fix after first
  render (moved from x=1 overlapping a point to x=8, hjust=1).

## Revision 2026-09-15 (post-review feedback)
- User asked for (1) visible lines separating the sub-panels and (2) error bars to show the 90%
  confidence interval rather than +/-1 SE.
- `plot_kgrid_coefs.r`: added `panel.border = element_rect(colour = "grey40", fill = NA,
  linewidth = 0.4)` to the shared `theme_kgrid` (draws a box around every facet in the 3x2 grids
  and around both patchwork panels in the first-stage figure).
- Added `CI90 <- qnorm(0.95)` and changed every `geom_errorbar` ymin/ymax from `coef -/+ se` to
  `coef -/+ CI90 * se` (family figures and the first-stage coefficient panel). `y_span` (used to
  pick the 0.1 vs 0.01 axis-label accuracy) now uses the CI90-scaled bounds too, so the accuracy
  choice reflects the wider bars.
- Re-ran the script; all 5 PNGs regenerated and visually re-verified (borders visible, bars
  visibly wider than the prior +/-1 SE version, no other regressions).

## Revision 2 2026-09-15 (SYR2 concentration figures)
- New request: same k-grid treatment for SYR2 Six-Year Review mean concentration (arsenic,
  nitrate, barium, selenium) rather than violation indicators. Entered plan mode (new data build
  step, per plan-first-workflow.md); plan saved to
  `~/.claude/plans/kgrid-syr2-concentration-coefficient-plots.md`.
- Key difference: the step-grid IV (post95:sulfur_mean0) is degenerate on the SYR2 sample (post95
  is identically 1 on all non-missing VALUE obs <=2005), so only OLS is estimated -- matches
  existing practice in `run_k2_6yr_tables.r` / `run_step_top3_outcomes.r`.
- Asked user via AskUserQuestion: 4 separate per-chemical figures vs 1 combined figure with
  chemical rows. User chose 4 separate figures (Recommended) -- coefficient scales differ ~1000x
  across chemicals (nitrate ~0.1 vs arsenic ~0.0001 mg/L per 10M ST), so a shared y-axis would
  flatten the smaller ones.
- `code/coal_mining_water_quality/run_kgrid_syr2_coefs.r`: new script. Generalizes
  `run_k2_6yr_tables.r`'s `build_dose_sample()` with an arm argument and the same placebo purity
  screen used in `run_kgrid_coefs.r`. 8 k x 2 arm x 4 chem = 64 OLS regressions (FE:
  PWSID + STATE_CODE^year, cluster ~PWSID). Verified pre-flight (read-only R check) that every
  cell has >=190 obs before writing any code -- no <30-obs skips expected or observed.
  Output: `clean_data/cws_data/kgrid_syr2_coefs.parquet` (64 rows). Gate 1 (k=2 main-arm vs
  `6yr_huc02fe_inorg_ravalli_2005_k2.tex` anchor: arsenic 0.0001/nitrate 0.1037/barium
  0.0130/selenium 0.0004) matched exactly to 4 decimals. Gate 2 (unexpected-skip scan): 0 skips.
- `code/coal_mining_water_quality/plot_kgrid_syr2_coefs.r`: new script, reads only the Step-1
  parquet. 4 figures (`kgrid_syr2_{arsenic,nitrate,barium,selenium}_coefs.png`), each a single row
  faceted by arm (main | placebo), 90% CI bars, panel border, one fixed Okabe-Ito colour per
  chemical (arsenic/nitrate reuse the same colour slots as the MR/MCL figures). Y-axis decimal
  accuracy computed per figure as one order of magnitude below that chemical's own CI span
  (`10^floor(log10(y_span))/10`) so arsenic/selenium render at ~1e-4/1e-5 precision instead of
  rounding to 0.
- All 4 PNGs visually inspected: correct k=1..8 ticks, zero line, panel borders, no sci notation,
  consistent per-figure decimal accuracy, k=2 main-arm points match the anchor. Selenium placebo
  bars shrink sharply from k=1/2 (SE~0.011-0.016) to k=3+ (SE~0.0004) -- checked the underlying
  parquet values directly; this is a genuine pattern in the estimates, not a rendering bug.
- Quality score: ~90. Not committing yet -- awaiting user review of the 4 new figures, per the
  same convention as the first batch.

## Revision 3 2026-09-15 (user question: upstream tonnage for placebo arm?)
- User asked how the "cumulative upstream coal tonnes" regressor is defined for the placebo arm,
  which by construction has no upstream mines.
- Verified in `build_step_instruments.py`: `production_linked_sum` in `step_instruments.parquet`
  is already arm-direction-correct at the source -- `main_pairs` (ancestor/upstream HUCs) feeds
  the main arm's sum, `placebo_pairs` (descendant/downstream HUCs) feeds the placebo arm's sum
  (lines 92-127, 240-241, 257-258). So the placebo-arm regression already used cumulative
  *downstream* coal tonnage -- the estimates in `kgrid_syr2_coefs.parquet` and all 4 PNGs were
  correct all along.
- Found one real (cosmetic) issue: `run_kgrid_syr2_coefs.r` named the pooled column
  `coal_prod_upstream_cumsum_10mst` for both arms (inherited verbatim from
  `run_k2_6yr_tables.r`, which is main-arm-only so the name was accurate there) -- misleading for
  placebo rows, where the quantity is actually downstream tonnage. Renamed throughout to the
  arm-neutral `coal_prod_linked_cumsum_10mst` and expanded the header comment to state the
  arm-direction mapping explicitly. Re-ran the script: identical numeric results (pure rename,
  same underlying `production_linked_sum` data), gate 1 still matches the k=2 anchor exactly. No
  change to `kgrid_syr2_coefs.parquet` contents or the 4 PNGs -- the renamed column never left the
  R script, so nothing downstream needed regenerating.

## Revision 4 2026-09-15 (user question: k=1 barium sign mismatch vs published table)
- User asked why k=1 barium in `kgrid_syr2_barium_coefs.png` was negative (-0.0103, SE 0.0141,
  n.s.) while `6yr_huc02fe_inorg_ravalli_2005.tex` shows it positive (+0.0171*, SE 0.0093). Root
  cause: `run_kgrid_syr2_coefs.r` used `PWSID + STATE_CODE^year` FE, not the published tables'
  `PWSID + huc02^year` FE -- a real spec difference, not a bug. `run_step_top3_outcomes.r` had
  already verified (2026-09-14 log) that the step-linkage k=1 sample reproduces the published
  table *exactly* under `huc02^year` FE, confirming the fix.
- Follow-up user question: why doesn't the step-linkage k=1 main-arm sample equal the static
  `minehuc_downstream_of_mine==1 & minehuc_mine==0` sample used by the published table? Answer:
  `build_step_instruments.py`'s own gate (lines 326-341) already checked this -- step-linkage k=1
  main arm is a strict superset (385 vs 340 CWSs; all 340 overlapping rows match with 0 diff). The
  45 extra CWSs are traced to a legacy `sdwismatch` mixing-exclusion rule (drops PWSIDs that mix an
  unclassified-HUC facility with a non-upstream one) that the step-instrument pipeline's simpler,
  independently-built intake linkage does not replicate (documented in
  `.claude/logs/2026-09-13-instrument-step-grid.md:76-80`).
- Entered plan mode (regression-spec change touching a build script + its verification gate + 2
  downstream output sets); plan saved to `~/.claude/plans/structured-twirling-spark.md`, approved.
- `run_kgrid_syr2_coefs.r`: joined `pwsid_huc02.parquet` onto `d6r` (mirroring
  `run_step_top3_outcomes.r`), changed the formula's FE from `STATE_CODE^year` to `huc02^year`
  (renamed `fml_state` -> `fml_huc02`), and replaced verification gate 1 (previously k=2 vs the
  `STATE_CODE^year`-based `..._k2.tex`, which was never a valid anchor for a `huc02^year` spec) with
  a k=1-vs-published-table gate requiring an *exact* match -- stronger than the old "same
  sign/rough magnitude" gate since this exact reproduction was already independently verified.
- Re-ran: gate 1 passed with a bit-identical match (arsenic 0.0023/0.0004, nitrate 0.0572/0.0922,
  barium 0.0171/0.0093, selenium 0.0033/0.0016 at k=1 main arm), gate 2 (unexpected-skip scan) 0
  skips. Re-ran `plot_kgrid_syr2_coefs.r`: all 4 PNGs regenerated. Barium k=1 main-arm point is now
  positive, matching the published table; effect decays smoothly with flow distance k across all 4
  figures under the new FE spec, no other regressions observed on visual inspection.
