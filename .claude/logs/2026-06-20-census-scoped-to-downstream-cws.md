# Session: 2026-06-20 — Census NHGIS download scoped to downstream-of-mine CWS

## Objective

Continue `.claude/logs/2026-06-19-census-block-download-handoff.md`, but scope of the
pull was redefined mid-session by the user (see Design Decisions). Plan approved and
saved at `Z:\Users\ek559\.claude\plans\humble-snuggling-mist.md` — **read that file
first** when resuming; it has the full approach, verified counts, and file list.

## Approach (summary — see plan file for full detail)

1. New script `get_downstream_service_areas.py` builds a 3-tier exposure-geography
   crosswalk for the 367 PWSIDs with `minehuc_downstream_of_mine==1` (ever):
   - 239 PWSIDs → matched to an EPA SABS service-area polygon
     (`raw_data/CWS_Boundaries_Latest/EPA_CWS_V1/EPA_CWS_V1.shp`)
   - 127 PWSIDs → no SABS polygon, fall back to county FIPS (derived from
     `Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_GEOGRAPHIC_AREAS.csv`,
     `AREA_TYPE_CODE=='CN'`), spanning 48 distinct counties
   - 1 PWSID (`SC2460011`) → truly unmatched, excluded with a caveat
   - Output: `clean_data/cws_data/downstream_mine_exposure_geo.parquet`
2. Rework `download_census_nhgis.py` to process **one census year at a time** (not all
   4 upfront): submit extract → download to temp dir → spatially filter against the
   exposure geography → write only the filtered/attributed subset to
   `raw_data/census/<year>/` → discard the temp dir before the next year.
   - Block + block-group shapefiles/CSVs: filtered via `gpd.sjoin(... ,
     predicate="intersects")` against SABS polygons (239) + assigned fallback county
     polygons (127), carrying `PWSID` through as an attribute.
   - County boundaries: intersected **universally for all 366 matched PWSIDs** (not
     just the 128 fallback ones) as a third geography level, producing a
     `PWSID × county_fips` crosswalk per vintage in `raw_data/census/<year>/county/`.
   - NHGIS extent restricted to 18 states (down from 33): AL, CO, FL, GA, IL, KS, KY,
     LA, MD, NC, OH, PA, SC, TN, UT, VA, WA, WV — derived dynamically from the
     crosswalk, not hardcoded.

## Design Decisions

| Decision | Rationale |
|---|---|
| Switch from nationwide 33-state pull to downstream-of-mine-only scope | User: only needs demographics for CWSs ever 1 HUC12 downstream of a mine; disk space was also tight (~25GB free vs 20-30GB estimate) |
| Keep the 128 SABS-less PWSIDs via county fallback instead of dropping them | User: "I want to keep the CWSs that lack a service area boundary if they have some sub-state geographical variable... replace their geography with the smallest geographical variable that can be matched" |
| County boundaries intersected for ALL 367 PWSIDs, not just the 128 fallback | User confirmed via AskUserQuestion: wants county as a universal third geography level (cross-check/coarser aggregate), not just a substitute |
| County shapefile is NHGIS's national `us_county_<year>_tl<basis>` product | Confirmed via metadata API: no state-clipped county shapefile exists; national file is tiny (~3,100 polygons) regardless |
| Block-group shapefiles confirmed available per-state for all 4 censuses | User asked directly; confirmed via metadata API (`010_blck_grp_1990_tl2000` ... `560_blck_grp_2020_tl2020`) — no design change needed, already in scaffold's `BG_SHAPE_BASE` |
| `minehuc_downstream_of_mine` already means exactly 1 hop downstream | Verified in `huc_coal_charac_geom_match.py:86-91` — `downstreamcoal` = mine HUC's `tohuc` renamed to `huc12`. No extra hop-distance logic needed. |
| SABS PWSID format matches project's PWSID format directly | Spot-checked: both are the standard 2-letter-state + 7-digit format (one stray all-digit PWSID in prod_vio_sulfur.parquet, immaterial) |

## Verification Results (pre-implementation, research phase)

- [x] Confirmed 367 downstream PWSIDs, 239/127/1 tier split, 18-state union — all via live read-only queries against `clean_data/cws_data/prod_vio_sulfur.parquet`, the SABS shapefile, and `SDWA_GEOGRAPHIC_AREAS.csv`
- [x] Confirmed NHGIS metadata: county shapefile names + national-only extent; block-group shapefile names + per-state availability, all 4 years
- [x] **Implemented and ran `get_downstream_service_areas.py`** (2026-06-20) — reproduces 367/239/127/1 exactly; 18-state union exactly matches the plan. Output written to `clean_data/cws_data/downstream_mine_exposure_geo.parquet` (367 rows; 239 with SABS geometry, EPSG:5070; re-read verified PWSID as string dtype).
- [x] **Confirmed NHGIS metadata API call shape** (2026-06-21) — `client.get_metadata_catalog('nhgis', metadata_type='shapefiles')` yields pages that are dicts with keys `data`/`pageNumber`/`pageSize`/`totalCount`/`links`; `data` is a list of dicts with a `name` field (2,114 shapefiles total). Confirmed live: `us_county_1990_tl2000`, `us_county_2000_tl2000`, `us_county_2010_tl2010`, `us_county_2020_tl2020` all present, plus the existing `BG_SHAPE_BASE` per-state names (`010_blck_grp_*` ... `560_blck_grp_*`).
- [x] **Implemented `download_census_nhgis.py` rework** (2026-06-21) — full rewrite: `EXTENT_CODES`/state list now derived at runtime from `downstream_mine_exposure_geo.parquet` (full 51-entry `STATE_FIPS` lookup kept for robustness, not hardcoded to 18); added national county shapefile to each year's extract; per-year loop now submits → waits → downloads to `tempfile.TemporaryDirectory()` → builds county crosswalk (`build_county_crosswalk`, universal sjoin + direct append) → builds block/BG exposure geometry (`build_blockbg_exposure_gdf`, 239 service-area + 127 county-tier polygons) → spatially filters block/BG shapefiles (`filter_census_gdf`, `gpd.sjoin(..., predicate="intersects")`) → filters the matching NHGIS CSVs by surviving `GISJOIN` → writes only filtered output to `raw_data/census/<year>/{block,blockgroup,county}/`. Compiles clean (`py_compile`).
- [ ] **County FIPS field derivation is unverified against real data** — `find_county_fips_column()` tries `STATEA`/`COUNTYA` first, falls back to slicing `GISJOIN` (`G+state(2)+0+county(3)`), with print statements logging columns/samples so a wrong assumption surfaces immediately during the 1990 smoke test rather than failing silently. Cannot verify further without submitting a real extract.
- [x] **User confirmed Step 3 cost estimate** (2026-06-21) — approved running the 1990 smoke test under the 18-state revised scope.
- [x] **1990 smoke test passed** (2026-06-21) — three real bugs found and fixed against live NHGIS data (none were guessable without a real extract):
  1. `wait_for_extract` only polls the lightweight status endpoint and returns the instant status flips to `completed`; `downloadLinks` lags behind by up to ~1 minute. Added a retry loop (30 attempts, 5s apart) in `process_year` before reading `dl["tableData"]`/`dl["gisData"]`.
  2. The *delivered* shapefile filenames (`AL_block_1990.shp`, `AL_blck_grp_1990.shp`, plus a nested nation-county file) do not match the *requested* shapefile names (`010_block_1990_tl2000`, etc.) — postal code instead of FIPS extent code, no TIGER-vintage suffix, and nested inside a subdirectory rather than flat. Replaced exact-filename lookups with `classify_shapefiles()`, which buckets every `.shp` under the temp dir by content (`"county" in name` / `"blck_grp" in name` / `"block" in name`) rather than guessing exact names.
  3. The 1990 county shapefile has **no `STATEA`/`COUNTYA` columns at all** (confirmed via printed column list) — `find_county_fips_column()`'s `GISJOIN` fallback was exercised for real and correctly derived county FIPS (`G4201330` → state `42`, county `133`, i.e. Centre County, PA) since NHGIS's county-level `GISJOIN` format (`G` + 2-digit state + `0` + 3-digit county) held exactly as documented.
  - Added `--reuse-extract <id>` and `--years` CLI flags to `download_census_nhgis.py` so debugging iterations could re-process an already-submitted extract instead of resubmitting (avoided burning ~4 extra extracts during the fix loop — extracts #3 and #4 were submitted before the bugs were found; #4 was reused for the final passing run).
  - Made `write_manifest`/`main()` read every year's results from `raw_data/census/manifest_data/<year>.json` (written by `process_year`) rather than only the years run in the current invocation, so running years incrementally still produces one cumulative manifest. One stale key bug (`bg_raw_rows` vs. actual `blockgroup_raw_rows`) found and fixed at this stage too — by then the real data was already written to disk, so the manifest was regenerated from the saved JSON without re-running the extract.
  - **Final verified 1990 output**: 717MB on disk (32GB free — comfortably inside budget, the original concern that drove the scope pivot). Block: 3,131,820 raw → 584,294 filtered (584k reflects that 127 of 366 PWSIDs use a *whole county* as their exposure geometry, by design, not a bug). Block group: 95,096 → 24,575. County: 3,141 → 172. County crosswalk: 463 rows covering all 366 matched PWSIDs (≥366 as expected, since service areas spanning multiple counties add rows). 0 null PWSIDs on every filtered shapefile.
- [x] **End-to-end run for 2000/2010/2020 — complete.** All three ran cleanly through the now-fixed pipeline (extracts #5/#6/#7), no further bugs surfaced. County FIPS fell back to the `GISJOIN` derivation for all of 1990/2000/2010/2020 — none of the four vintages' national county shapefile has `STATEA`/`COUNTYA` columns (1990/2000 use `STATE`/`COUNTY` name fields only; 2010 uses `STATEFP10`/`COUNTYFP10`; 2020 uses `STATEFP`/`COUNTYFP` — all without the "A"-suffix NHGIS convention assumed in the original plan). 0 null PWSIDs on every filtered shapefile, every year. County crosswalk covered all 366 matched PWSIDs in every year (462-463 rows).
  | Year | Block (raw→filtered) | BG (raw→filtered) | County (raw→filtered) | Disk |
  |---|---|---|---|---|
  | 1990 | 3,131,820 → 584,294 | 95,096 → 24,575 | 3,141 → 172 | 717 MB |
  | 2000 | 3,399,365 → 594,473 | 87,495 → 20,759 | 3,141 → 172 | 783 MB |
  | 2010 | 4,633,903 → 790,258 | 92,252 → 20,266 | 3,221 → 171 | 2.2 GB |
  | 2020 | 3,475,464 → 604,123 | 102,658 → 20,885 | 3,221 → 172 | 1.8 GB |
  **Total: 5.4 GB**, 27 GB still free — comfortably inside budget (vs. the original 20-30GB nationwide estimate that drove the scope pivot in the first place).
- [x] `raw_data/census/manifest.md` regenerated cumulatively from all 4 years' `manifest_data/<year>.json` files — final content verified, scope/caveats/row-count table all correct.

## Status: COMPLETE

All steps of the plan (`Z:\Users\ek559\.claude\plans\humble-snuggling-mist.md`) are done:
`get_downstream_service_areas.py` (Step 1), the reworked `download_census_nhgis.py`
(Step 2), the cost re-estimate and user confirmation (Step 3), and the year-by-year
run with verification (Step 4). Output lives at `raw_data/census/<year>/{block,
blockgroup,county}/` for 1990/2000/2010/2020, plus `raw_data/census/manifest.md`.

## Design Decisions (added during implementation)

| Decision | Rationale |
|---|---|
| County-fallback distinct-county count is **57**, not the plan's preliminary **48** | The plan's research-phase number counted distinct `ANSI_ENTITY_CODE` values alone (3-digit, repeats across states); the script computes the full 5-digit `county_fips` (state FIPS + entity code), which is the correct distinct-county count. Tier counts (239/127/1) and the 18-state union are unaffected and match the plan exactly. |
| State assigned from the PWSID prefix (2-letter postal code), not from `STATE_CODE`/`PRIMACY_AGENCY_CODE` | Tried `STATE_CODE` first since it's unique per downstream PWSID — but it diverged from the PWSID prefix for a subset of PWSIDs (e.g. some `GA`-prefixed PWSIDs carry `STATE_CODE` of FL/VA/CA), inflating the state union to 22 and counties to 59. That field is `PRIMACY_AGENCY_CODE` and can reflect administrative primacy rather than physical location. Reverted to the PWSID prefix (the SDWIS convention), which reproduces the plan's exact verified 18-state list. `STATE_CODE` is used only as a fallback for the one all-numeric PWSID (`080890001`) whose prefix isn't a 2-letter postal code. |

## Open Questions / Blockers

- None outstanding — plan fully approved by user as of 2026-06-20. Paused for the day
  mid-Step-2 (see Next Steps) at the user's request — no blocker, just a stopping point.

## Next Steps

None — this task is complete. If resuming related work later:
- The exposure crosswalk (`clean_data/cws_data/downstream_mine_exposure_geo.parquet`)
  and the filtered census data (`raw_data/census/<year>/...`) are the reusable
  artifacts; no need to regenerate either unless the upstream mining/HUC pipeline or
  the 367-PWSID downstream definition changes.
- Likely next step in the broader project (per `writeup/cws_exposure_backcasting.tex`)
  is areal-interpolation backcasting using these filtered block/block-group files —
  not started, not part of this task.
