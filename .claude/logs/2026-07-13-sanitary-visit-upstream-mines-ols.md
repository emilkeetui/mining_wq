# Session: 2026-07-13 — Sanitary visit / upstream mines OLS on main 2SLS panel

## Objective
Build a CWS-year OLS table: DV = formal enforcement, regressors = sanitary
visit binary + number of upstream coal mines. Col 1 no FE, col 2 year FE,
col 3 CWS FE. Print to console.

## Changes Made
- `code/coal_mining_water_quality/sanitary_visit_upstream_mines_ols.r`: new
  script. First pass built a synthetic CJ(PWSID, year) skeleton off the
  strictly-downstream sample (349 CWS x 21 yr = 7,329 rows) — user corrected
  this; the "main 2SLS panel" is the D1 sample used in didhet.r /
  enforcement_chain_d12.r, N=6,225 after FE demeaning. Rewrote to replicate
  that exact construction: `prod_vio_sulfur.parquet` filtered to
  `minehuc_downstream_of_mine==1 & minehuc_mine==0 & year 1985-2005 &
  PWSID != "WV3303401"`, native PWSID-year rows (not a full CJ skeleton),
  merged with `any_snsv` (VISIT_REASON_CODE %in% c("SNSV","SSVF")) from
  SDWA_SITE_VISITS.csv and `any_formal` (ENF_ACTION_CATEGORY=="Formal") from
  SDWA_VIOLATIONS_ENFORCEMENT.csv, same logic as enforcement_chain_d12.r.
  Confirmed: 6,232 raw PWSID-years, 6,225 after 7 FE singletons dropped in
  the CWS-FE column — matches h3_inf_formal_d12.tex exactly.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Use native PWSID-year rows from prod_vio_sulfur.parquet, not CJ(PWSID,year) skeleton | User specified "main 2SLS panel dataset which contains 6225 observations" — that N only reproduces from the D1 sample's own rows + FE singleton drop, not a synthetic full panel |
| Re-derive any_snsv/any_formal from raw SDWA CSVs rather than clean_data | prod_vio_sulfur.parquet has no site-visit or enforcement columns; no existing clean_data file has them merged in either (confirmed via glob) — user approved re-deriving via AskUserQuestion |
| any_snsv = SNSV/SSVF only (not SNSP) | Matches enforcement_chain_d12.r's H2b definition exactly, not the 3-code definition used in some sanitary_visit_*.r scripts |

## Verification Results
- [x] Script runs end-to-end (Rscript --vanilla)
- [x] Output (etable) printed to console
- [x] N=6,225 in CWS-FE column matches h3_inf_formal_d12.tex reference exactly

## Follow-up: CWS-coal-mine ownership question
User asked whether any CWSs are owned by a coal mining company. No
systematic ownership field exists (OWNER_TYPE_CODE is generic
federal/local/private/state/native-American, not operator identity).
Name-matched PWS_NAME for "coal"/"mine"/"colliery": most hits are place
names (Coalton, Coalport, Minersville, etc.), but WV3300803 "CLINCHFIELD
COAL CO" stands out as plausibly company-owned (minehuc_mine=0 for that
PWSID, worth double-checking the geo match). Did not pursue an MSHA
operator-name x SDWIS PWS_NAME/ORG_NAME cross-match — flagged as a
possible follow-up, not yet approved by user.

## Open Questions / Blockers
- Does the user want an MSHA-operator x SDWIS ownership cross-match to
  systematically identify coal-company-owned CWSs? Not yet started.
