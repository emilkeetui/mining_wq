# Session: 2026-07-17 — Reconcile mr_concentration_lag_national_downstream_states_yearly.r outcome

## Objective
Reconcile `mr_concentration_lag_national_downstream_states.tex` (reading-level) and
`_yearly.tex` (CWS-year) so they test the same hypothesis at different aggregation grains,
per the divergence documented in
`.claude/logs/2026-07-16-mr_concentration_lag_downstream_states_vs_yearly_comparison.md`.

## Approach
User chose: make `_yearly.r`'s outcome reading-anchored (nest the reading-level
"MR onset in the forward window of THIS reading" logic inside the CWS-year lag window),
rather than the current "any MR onset that calendar year" outcome. New standalone script,
original `_yearly.r`/`.tex` untouched per no-overwrite rule.

## Key Finding
`mr_same_fwd`/`mr_same_fwd6mon` are already precomputed at reading level in
`clean_data/mr_concentration_lag_national_nitrate.parquet` — no need to re-derive via a
fresh SDWA_VIOLATIONS_ENFORCEMENT join; reuse existing columns, drop that join from the
reconciled script.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| New file `_yearly_reconciled.r`, not in-place edit | Matches data-safeguards no-overwrite rule and prior session's `_leadonly_test.r` precedent |
| New outcome `mr_reading_triggered_lag{6,12}` built from lag-window readings' own `mr_same_fwd`/`mr_same_fwd6mon` | Nests downstream_states' per-reading causal logic at CWS-year grain |
| Drop SDWA_VIOLATIONS_ENFORCEMENT join | Reading-level mr_same_fwd columns already encode this |
| RHS (near_mcl_lead/lag, mean_conc_z_lead/lag) unchanged | Isolates the outcome-definition fix as the only design change |

## Verification Results
- [x] Script runs end-to-end, exits clean
- [x] Output exists at `output/reg/mr_concentration_lag_national_downstream_states_yearly_reconciled.tex`, non-zero
- [x] CWS-year row count matches existing `_yearly.r`: 480,015 rows (53,335 CWSs x 9 years)
- [x] Coefficient sign now agrees with `_downstream_states.tex`: `near_mcl_lag6`/`lag12` are
      positive and highly significant (0.0937***/0.0785*** with FE for 6mo;
      0.1314***/0.1028*** with FE for 12mo) — same direction as `_downstream_states.tex`'s
      `near_mcl` coefficient (0.0042*, 0.0015*). Reconciliation resolved the sign flip
      documented in the 2026-07-16 comparison log: once the outcome is reading-anchored
      (an MR onset in a lag-window reading's OWN forward window) instead of "any MR onset
      that calendar year," both specs now say the same thing — a near-MCL reading raises
      the likelihood of an MR violation following it.
- Note: `near_mcl_lead6/lead12` (readings still in the future relative to the CWS-year) are
  negative and significant — expected, since a lead-window reading's own forward outcome by
  definition cannot yet be reflected in a CWS-year mechanically defined off the LAG window;
  this coefficient is picking up a different (correlational, not mechanical) relationship
  and should not be over-interpreted as "reconciled" the same way lag was.

## Key Simplification
`mr_same_fwd`/`mr_same_fwd6mon` already precomputed at reading level in
`clean_data/mr_concentration_lag_national_nitrate.parquet` — dropped the
SDWA_VIOLATIONS_ENFORCEMENT join entirely from the reconciled script vs. original `_yearly.r`.

## Open Questions / Blockers
- Bash-tool Rscript.exe invocations segfault this session; used PowerShell for all R runs
  (works fine).

## Next Steps
- None pending; awaiting further user direction. Original `_yearly.r`/`.tex` left untouched.
