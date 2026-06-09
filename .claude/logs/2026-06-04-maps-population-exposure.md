# Session: 2026-06-04 — Maps and population exposure figures

## Objective
Update coal production change maps and add a downstream population exposure figure.

## Changes Made
- `map_coal_prod_changes.py`: replaced the upstream-mines-count panel with a new
  population exposure panel showing proportionate circles at intake HUC12 centroids
  sized by average population served, colored red (upstream mining rose) or blue
  (upstream mining fell) 1985–2005; also fixed inverted red/blue color coding in
  the production-change panels
- `population_exposure_map.r`: fixed variable name (`num_coal_mines_upstream` →
  `num_coal_mines_upstream_sum`); switched population aggregation from mean to
  period-length-adjusted sum (÷5 early, ÷6 late); added national average diagnostic

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Bubble size ∝ population, color = mining direction | Separates exposure magnitude from treatment direction |
| Period-length-adjusted sum in pop_exposure_map.r | Mean across years underweighted longer periods; sum/N gives avg annual exposure |
| Red = increase, Blue = decrease | Conventional: red = more activity/risk |

## Verification Results
- [x] Scripts run end-to-end
- [x] Figures updated in output/fig/
- [x] Committed and pushed to fix-het-regression-block

## Open Questions / Blockers
- None active

## Next Steps
- PR and merge fix-het-regression-block to master when satisfied
