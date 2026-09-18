# Session: 2026-09-17 — Fix spurious Year FE checkmark alongside State×Year FE

## Objective
Fix `job_talk.tex` regression tables that showed both "Year fixed effects" and
"State × year fixed effects" checked in the same column when `year` is
collinear with (nested inside) `STATE_CODE^year`. Plan:
`~/.claude/plans/encapsulated-munching-hearth.md`.

## Changes Made
- `code/coal_mining_water_quality/k2_common.r`: replaced `fe_row_year`'s
  `chk_all` (always-checked) mask with a proper `fe_year` mask that checks
  for a bare `"year"` term per column's FE spec string.
- `code/coal_mining_water_quality/run_k2_main_tables.r`: removed the
  redundant literal `+ year` term from `FE_TWO`, `fe_state_yr`, the `fs_m`
  formula, and the `m1` (exclusion test) formula, all now `PWSID +
  STATE_CODE^year` instead of `PWSID + year + STATE_CODE^year`. Removed the
  "Year fixed effects" entry from `el_fs` (first-stage table, single-column,
  uniformly absent). Fixed the hand-typed checkmark row for
  `exclusion_test_num_facilities_k2` (column 1 no longer checked for Year FE).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Updated two `stopifnot()` anchor values (arsenic MR SE 1.56→1.55; first-stage F 49.10→49.20) rather than reverting the formula fix | The plan assumed removing the redundant `+year` term would be purely cosmetic (fixest silently drops collinear terms when fitting). Verified directly: point estimates are bit-identical (10 digits) with/without the redundant term, but fixest's clustered-SE small-sample dof correction is *not* identical — it's computed with a slightly different degrees-of-freedom count depending on whether the collinear `year` term is nominally declared. This is a small, systematic, expected difference (not floating-point noise), confirmed with the user via AskUserQuestion before updating the anchors. |

## Verification Results
- [x] Script runs end-to-end (`run_k2_main_tables.r`, exit 0)
- [x] `MR anchor gate PASSED` and `First-stage F gate PASSED` (with corrected anchor values)
- [x] Output files exist at expected paths (14 `.tex` files under `output/reg/`)
- [x] Diffed all 7 affected table pairs against pre-edit versions: changes are
      confined to FE checkmark rows, the tiny SE/F-stat shifts described
      above, and pre-existing unrelated `\cline` header changes already
      uncommitted from a prior session — no coefficient or N changes
- [x] Visually confirmed no column shows both "Year fixed effects" and
      "State × year fixed effects" checked simultaneously in any of the 7 tables
- [x] Recompiled `job_talk.pdf` (pdflatex → biber → pdflatex ×2), all passes
      exit 0, 0 undefined references, 56 pages

## Open Questions / Blockers
- `h2_snsv_d12_k2` (and its `_present` companion) now shows a "Year fixed
  effects" row that is blank across *all* columns (single FE spec table:
  every column already shared `PWSID + STATE_CODE^year`). Per
  `table-notes-conventions.md` Rule 7 / `table-figure-formatting.md` Rule 7,
  a uniform-across-columns FE row (checked *or* blank) should be omitted
  entirely with FEs stated in the notes instead — this applies to all three
  FE rows in that table (Utility, Year, State×year), not just Year. This is a
  pre-existing structural property of `render_panel_k2()` (always emits 3
  checkmark rows regardless of whether they vary) and was out of scope for
  this plan, which only asked to fix the checkmark-value bug, not add
  row-omission logic. Flagged, not fixed.

## Next Steps
- If desired, a follow-up task could add uniform-FE-row omission logic to
  `render_panel_k2()` (general fix, would also affect any other
  single-FE-spec table using this renderer), covering the `h2_snsv_d12_k2`
  case above.
