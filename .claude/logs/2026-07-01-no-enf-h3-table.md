# Session: 2026-07-01 — Add No Enforcement column to h3_inf_formal_d12 table

## Objective
Add a third dependent variable "No enforcement" (binary: 1 if CWS has no ongoing enforcement in that year) to the h3_inf_formal_d12.tex table, alongside existing informal and formal enforcement columns.

## Changes Made
- `code/coal_mining_water_quality/enforcement_chain_d12.r`:
  - Added `panel_d1$no_enf <- 1L - panel_d1$any_enf` after existing any_enf/any_informal/any_formal integer casts
  - Added OLS/RF/IV formulas (`fml_ols_ned1`, `fml_rf_ned1`, `fml_iv_ned1`) and fitted models (`ols_ned1`, `rf_ned1`, `iv_ned1`) following the same spec as informal/formal
  - Extended `f_vec_d1` from 6 to 9 entries (adds blank, blank, F-stat for cols 7-9)
  - Added `"no_enf" = "No enforcement"` to `dict_enf`
  - Extended `etable()` call to include `ols_ned1, rf_ned1, iv_ned1` as cols 7-9
  - Updated notes to report no-enforcement share (78.7% of panel)

## Verification Results
- [x] Script runs end-to-end (exit 0)
- [x] Output exists at `output/reg/h3_inf_formal_d12.tex`
- [x] Table header shows three panels: "Any informal enf", "Any formal enf", "No enforcement"
- [x] Notes correctly label cols 7-9 and report 78.7% baseline

## Open Questions
- None
