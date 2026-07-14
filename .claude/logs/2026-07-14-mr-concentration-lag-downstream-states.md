# Session: 2026-07-14 — mr_concentration_lag national table restricted to downstream-2SLS states

## Objective
Create a variant of `mr_concentration_lag_national.r` / `output/reg/mr_concentration_lag_national.tex`
restricted to CWSs in states that have >=1 CWS in the main downstream 2SLS sample
(`minehuc_downstream_of_mine==1 & minehuc_mine==0`, years 1985-2005), rather than the fully
unrestricted national sample.

## Key Context
- Downstream 2SLS sample states (1985-2005), 22 states: AL, CA, CO, FL, GA, IL, KS, KY, LA, MD,
  NC, NJ, NY, OH, OR, PA, SC, TN, UT, VA, WA, WV (excluded a spurious "0" STATE_CODE, 1 PWSID).
- `prod_vio_sulfur.parquet`: STATE_CODE (chr), minehuc_mine/minehuc_downstream_of_mine (int),
  year (int) — all match CLAUDE.md glossary.
- `mr_concentration_lag_national_nitrate.parquet` has no state column; PWSID is prefixed with
  2-letter state code (e.g. "AL0000303") — state derived via substr(PWSID, 1, 2).
- No explicit YEAR 1985-2005 filter needed on the national nitrate data — it's SYR2, already
  confined to 1998-2005.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Derive state from PWSID prefix rather than a join | No state col in national parquet; PWSID prefix is the standard SDWIS convention and was verified directly |
| New separate script/output file, don't touch existing national table | Reference script/table stays intact as the fully-unrestricted specification |
| Skip explicit year filter | SYR2 data already 1998-2005; redundant given the plan discussion |

## Verification Results
- [x] Script runs end-to-end (exit 0, no errors)
- [x] Output exists: `output/reg/mr_concentration_lag_national_downstream_states.tex`, non-zero
- [x] Row counts plausible: 1,052,487 -> 546,520 rows after state filter (18 of 22 target
      states actually represented in the national nitrate data; 53,335 PWSIDs, 541,483 obs
      after singleton FE drop)
- [x] Table spot-checked: correct 4-column headers, plausible N, no `??`/`\undefined`, stars
      legend correct, notes render below table (adjustbox nesting correct)

## Open Questions / Blockers
- None

## Next Steps
- None — task complete.
