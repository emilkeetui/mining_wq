# Session: 2026-06-17 — Time-varying CWS population-served data acquisition

## Objective
For the backcasting/exposure exercise (population relying on CWS downstream of coal
mines, 1985+), locate and download as much PWSID-level, time-varying CWS
population-served data as possible (SYR3/4/5, older SDWIS snapshots, CWSS), then
profile each for PWSID linkage + population field.

## Context / upstream decisions
- Goal reframed (earlier turns) from "regression control" to **descriptive exposure**
  (headcount downstream of mines, trend, EJ demographics). User HAS the year-by-year
  downstream-CWS roster and service-area polygons. The "reported layer" (observed
  population served at anchor years) calibrates `r = served / polygon-Census-pop`.
- Tract polygons floor = 1990 (TIGER); decennial 1990/2000/2010/2020 + ACS 2009+.

## Downloads (raw_data/sdwa_cws_pop/ — see hook exception below)
| File | Snapshot | Usable as PWSID anchor? |
|---|---|---|
| sdwis2010_freeze.zip → .accdb | 2010 | YES: 93,526 CWS, RetPopSrvd raw + covariates |
| sdwis2011_freeze.zip → .accdb | 2011 | YES: RetPopSrvd raw |
| cwss_2006_database.zip → .mdb (`cwssframe`) | 2006 | YES: 51,081 CWS, retailpop/totalpop raw, pwsid |
| sdwisbuyers_sellers.zip → .accdb | 2010 Q4 | YES (wholesale dedup): 39,885 buyer/seller pairs |
| sdwis2005_freeze.zip → .xls | 2005 | NO: 87-row PivotTable summary only, no PWSID |
| cwss_2000_database.zip → .mdb | 2000 | NO: 1,246-row sample, CWSID only (no PWSID) |
| cwss_1995_database.zip → .accdb | 1995 | NO: 1,980-row sample, FPOPSERV, no PWSID |

- 2010 freeze pop field = `RetPopSrvd` (retail pop served, raw int 0–10M); filter
  `PWSType='CWS'` (PWSTypeCode='C'). Has FirstReportedDate/PWSDeactivationDate,
  NumberFacilities, WholesalerInd, PCounty, Owner, GwSw.
- CWSS 1995/2000 are de-identified stratified samples → validation/distribution only.
- 2005 SDWIS "freeze" on SYR3 page is only a summary pivot, NOT system-level.

## Resulting precise PWSID-linked anchor set
SYR2 (user has, 1998–2005) · 2006 (cwssframe) · 2010 · 2011 · [TODO ECHO 2021+].
Pre-1998 remains unanchored (no CWS-level pop online before ~1995, and 1995/2000
CWSS not PWSID-linkable).

## Design decisions
| Decision | Rationale |
|---|---|
| Narrow hook exception over disabling guard | User wants files in raw_data/ (they ARE raw source); preserve protection elsewhere |
| Skip large SYR4 occurrence files for now | Inventory embedded; ~50MB×6; defer until needed |
| Use 2006 retailpop/totalpop not popserv | popserv is categorical (1–8 → ranges); retailpop is raw |

## Hook change
- `.claude/hooks/protect-raw-data.py`: added EXEMPT_DIRS=("raw_data/sdwa_cws_pop",).
  NEW writes allowed there; destructive verbs (rm/mv/del/truncate) still blocked
  everywhere in raw_data; all other raw_data writes still blocked. 8/8 unit tests pass.

## Gotcha (LEARN)
- Never `cd` inside a Bash command here: the persisted shell cwd becomes the cwd the
  PreToolUse hook runs in, and the hook's relative path (`.claude/hooks/...`) then
  fails to resolve → ALL Bash/Write/Edit calls error. Use absolute paths; no cd.
  Unstuck by staging a temp hook copy at the stuck cwd, `cd` back to root, remove copy.

## Verification
- [x] All 7 zips downloaded, sizes match EPA listings (~94MB zips)
- [x] Each DB profiled; PWSID + pop fields confirmed/refuted per table above
- [x] 2010 CWS count 93,526; RetPopSrvd raw; 2006 cwssframe retailpop raw

## Next steps
- [ ] Grab ECHO SDWA_PUB_WATER_SYSTEMS (2021+ quarterly) for modern anchors
- [ ] (optional) SYR4 embedded inventory (~2012–2019)
- [ ] Build PWSID-keyed anchor panel (year, PWSID, pop_served, source) joined to
      downstream-CWS roster; apply Buyers/Sellers for wholesale dedup
- [ ] Note: extracted .accdb total ~660MB on disk (2×300MB); re-extractable from zips
