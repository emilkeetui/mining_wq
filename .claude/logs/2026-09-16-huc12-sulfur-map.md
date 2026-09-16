# Session: 2026-09-16 — HUC12 sulfur map

## Objective
Create a choropleth map of HUC12 boundaries colored by mean coal sulfur
content (% of coal weight), styled/zoomed like `map_huc12_main_sample.png`.

## Changes Made
- `code/coal_mining_water_quality/map_huc12_sulfur.py`: new script. Reads
  `clean_data/huc_coal_charac_geom_match.parquet`, filters to `minehuc == "mine"`
  HUC12s (sulfur is a coal-seam characteristic, constant per HUC12 across years
  so `sulfur_colocated` is averaged only to collapse the year panel to one row),
  merges to HUC12 geometries (Appalachian-bbox load, same as the sibling map
  script), reprojects to EPSG:5070, and plots with a sequential `OrRd` colormap
  and colorbar labeled "Mean Sulfur (% of Coal Weight)".
- `output/fig/map_huc12_sulfur.png`: new output (did not previously exist).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Restrict to `minehuc == "mine"` HUC12s only | Only mine HUC12s carry an intrinsic coal-seam sulfur value (`sulfur_colocated`); upstream/downstream HUC12s have no coal of their own to color by. |
| Sequential single-hue colormap (`OrRd`) | Sulfur % is a magnitude variable — dataviz skill calls for sequential (light→dark, one hue), not a rainbow/diverging scale. |
| Same bbox/extent logic as `map_huc12_main_sample.py` | User referenced that file as the style/zoom template; confirmed by inspection it is also a full-CONUS extent (mine HUC12s are naturally scattered across basins), so no further zoom was needed beyond matching that script's clip-to-bounds approach. |

## Verification Results
- [x] Script runs end-to-end (exit 0)
- [x] Output exists at `output/fig/map_huc12_sulfur.png`
- [x] 1,116 mine HUC12s all matched to geometries; sulfur range 0.0–6.8%, no scientific notation on colorbar

## Open Questions / Blockers
- Not yet embedded in `main.tex`/`job_talk.tex` — user didn't ask for that; flag if they want it added to the writeup.

## Next Steps
- None unless user requests embedding in the paper or a different sample restriction (e.g. main 2SLS sample only).
