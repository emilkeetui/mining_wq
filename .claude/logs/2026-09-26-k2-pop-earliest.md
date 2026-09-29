# Session: 2026-09-27 — k2 main-sample earliest population count

## Objective
Headline "people served by the k2 main-sample utilities" number, measured per
utility from the earliest-dated source (plan: `k2-main-sample-earliest-population-count.md`).

## Changes Made
- `code/coal_mining_water_quality/count_k2_pop_earliest.py` (new): roster replicates
  `build_k2_panel("main")` (A2, 1985–2005; assert 582 passes); reuses
  `build_cws_reported_ratio.py` loaders; adds CWSS 1995/2000 loaders + SDWIS 2024 fallback;
  cascade = earliest year, source priority tie-break.
- `clean_data/cws_data/k2_pop_earliest.parquet` (new): 582 rows, one per PWSID
  (PWSID str, year int64, pop_reported, source, is_wholesale_seller).

## Design Decisions / Data findings
| Decision | Rationale |
|---|---|
| CWSS 1995 skipped | Has PWSID (Screener `C101`) but population only as 8-level band `FPOPSERV`; no numeric count. 20 roster utilities responded. |
| CWSS 2000 skipped | Numeric `PeopleServiced` exists, but systems keyed by internal `CWSID`; no PWSID in DB. CWSID↔1995 ID collisions (120) are coincidental (size bands disagree). |
| SDWIS July 2005 freeze not used | File on disk is a state × size-class pivot table, not system-level. |
| Effective cascade | SYR2 (1998–2005) → CWSS2006 → SDWIS2010 → SDWIS2011 → SDWIS2024. |

## Verification Results
- [x] Exit 0; roster assert 582 passes (10,782 utility-years)
- [x] Output 582 rows, PWSID unique, str dtype
- Gross total 3,311,993; wholesale-adjusted 2,428,091 (32 sellers whose buyer is in sample)
- By source: SYR2 231 utils / 1.90M (57%); CWSS2006 197 / 1.33M (40%); SDWIS2010 145 / 0.08M; SDWIS2024 9 / 549
- Median utility 200, mean 5,691, max 250,000. No utility missing.
- Sanity: 2024 SDWIS total for same roster 3,635,713 (earliest/2024 = 0.91)
- Spot-check: TN0000366 SYR2 1998 = 206,145 vs 254,671 in 2024; PA5020038 250k (2006–2011) vs 520k (2024).

## Open Questions
- No pre-1998 numeric population is linkable to PWSID with data on disk; earliest dates are 1998+.
