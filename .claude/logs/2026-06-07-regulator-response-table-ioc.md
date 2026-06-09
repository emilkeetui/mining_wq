# Session: 2026-06-07 — Regulator response table IOC revision

## Objective
Revise `regulator_response_by_viol_type.r` to restrict sample to the main downstream 2SLS sample and produce a two-column IOC MR vs IOC MCL table.

## Changes Made
- `code/coal_mining_water_quality/regulator_response_by_viol_type.r`: Three changes:
  1. Sample now uses actual downstream PWS IDs (`minehuc_downstream_of_mine == 1 & minehuc_mine == 0`) rather than all CWSs in downstream states (349 CWSs vs. the prior broader set)
  2. Groups reduced to `ioc_mr` and `ioc_mcl` — rules 331/332/333 only (nitrate, arsenic, inorganic chemicals); radionuclides (340) excluded
  3. Table changed from 3-column (`lrr` + label) to 2-column (`lrr`); `make_frame` and all `\multicolumn` spans updated accordingly
  4. `rule_num` added to the violation-level collapse so the IOC filter works post-collapse

## Verification
- Script exits 0
- Output: `output/sum/regulator_response_by_viol_type.tex` — 1,273 IOC MR violations, 16 IOC MCL violations
- LaTeX structure confirmed correct (`lrr`, two data columns, notes updated)

## Open Questions
- IOC MCL N=16 is very small; percentages in that column should be interpreted cautiously
