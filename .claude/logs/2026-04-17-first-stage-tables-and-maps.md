# Session: 2026-04-17 — First-stage tables, FWL scatter, population exposure maps

## Objective
Add first-stage regression tables for downstream 2SLS specifications, produce a
Frisch-Waugh-Lovell scatter plot of the first stage, and map the geographic shift
in population exposed to upstream coal mining before and after ARP Phase I.

## Changes Made

### run_main_tables.r
- Added `storage_list_name` and `subheader` params to `tsls_reg_output_main` to
  accumulate first-stage feols objects in a global list (mirrors didhet.r pattern)
- Added `first_stage_table()` function producing two-level-header etable
- Loop now calls `first_stage_table()` once per sample × violation type

### code/coal_mining_water_quality/first_stage_scatter.r (new)
- Frisch-Waugh scatter: both upstream mine count and instrument (post95×sulfur_unified)
  residualized on PWSID + year FEs via `lm()` with factor dummies
- Used `lm()` rather than `fixest::feols` residuals to avoid row-alignment issues
  (feols residuals are unnamed vectors in this version of fixest)
- Slope = −0.081, equals first-stage coefficient by FWL theorem
- Downstream-only sample (n = 6,232)

### code/coal_mining_water_quality/population_exposure_map.r (new)
- Maps total population served by CWSs downstream of active coal mines by state
- Two-panel choropleth: 1985–1989 vs 2000–2005, log-transformed YlOrRd, white = no exposure
- Net-change map: symmetric log10 diverging scale so small changes remain perceptible
  alongside PA's large decline (−831K); white for no-data states
- Installed `tigris` package for US states shapefile

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Residualize both variables (FWL) in scatter | Slope equals first-stage coefficient; user initially asked for raw instrument on x-axis but reverted to full FWL |
| `lm()` with factors for FE residualization | `fixest::demean` version-sensitive; feols residuals unnamed — lm guarantees alignment |
| Symmetric log10 transform on change map | PA's −831K dominates linear scale, compressing all other changes to white |
| White for no-data states on change map | User preference: near-zero change ≈ no change; blending acceptable |
| First-stage tables grouped by sample × vio type | One table per (dwnstrm/dwnstrmcolocate) × (minevio/nonminevio), cat specs as subheaders |

## Verification Results
- [x] `run_main_tables.r` runs end-to-end, exit 0
- [x] 4 first-stage .tex tables exist in output/reg/
- [x] `first_stage_scatter.r` runs end-to-end, exit 0, figure saved
- [x] `population_exposure_map.r` runs end-to-end, exit 0, both figures saved
- [x] All changes committed: 8242bf1

## Open Questions
- Are there western CWSs in the dataset at all? (user asked but then cancelled the query)
- Population exposure maps use downstream-only CWSs; should colocated CWSs also be included?
