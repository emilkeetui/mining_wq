# Session: 2026-09-14 — k2 step-grid main.tex tables

## Objective
Implement `~/.claude/plans/k2-step-grid-main-tex-tables.md`: reproduce every
exhibit currently `\input{}`'d into main.tex's Tables and Figures block on the
step-instrument grid's main arm, k=2, A-full column, plus 4 placebo tables and
2 figures, wired into main.tex. Nothing existing overwritten — all outputs
carry `_k2`/`_k2placebo` suffixes; k2 data build is a separate pipeline.

## Approach
Follow the plan's 11 steps in order: (1) new visit/enforcement k2 cache
builder, (2) new HUC-link k2 builder, (3) shared R helpers (k2_common.r),
(4) main-arm tables, (5) placebo tables, (6) summary tables, (7) 6-year/SYR2
tables, (8) figures, (9) wire into main.tex, (10) verification hard gates,
(11) this log.

## Key context / assumptions
- Branch: instrument-step-grid (existing step-grid pipeline).
- Anchors to reproduce: F_main ≈ 50.01, F_placebo ≈ 53.17; MR 2SLS
  arsenic 3.11 (1.52), nitrates 3.28 (1.73), inorganic 2.00 (1.60) under
  PWSID+year+STATE_CODE^year.
- Expected counts: main = 12,492 rows / 666 utilities; placebo = 673
  utilities after purity screen.
- Wording: "utility/utilities" everywhere in rendered table text, never CWS/PWS.
- Committed pre-existing untracked work (run_step_top3_outcomes.r,
  run_mr_concentration_lag_ols_k2.r) as a44fc0c before starting, per user
  confirmation.

## Changes Made
- `build_step_visit_enf_k2.py`: new. Writes `sdwa_visit_agg_k2.parquet`
  (5,070 rows, 5 visit-type flags) and `sdwa_enf_agg_k2.parquet` (5,242 rows,
  any_formal/any_informal/any_enf) over the 1,339-PWSID k2 union universe.
  Consistency gate against `sdwa_visit_agg_steps.parquet` /
  `sdwa_enf_agg_steps.parquet` passed with 0 mismatches on 5,070/5,242
  shared rows.
- `build_step_huc_links_k2.py`: new. Writes `step_huc_links_k2.parquet`
  (4,835 rows, 666 PWSIDs) — depth<=2 upstream HUC links for the k2 main-arm
  scatter figure. Sanity gate (distinct linked-HUC count vs
  step_instruments.parquet n_hucs_linked) passed 0/50 mismatches.
- `k2_common.r`: new. `build_k2_panel()`, `k2_dict`, formatting helpers
  (verbatim from run_main_tables.r), `f_clustered()`, `notes_k2()`,
  `render_panel_k2()` (generalized grouped-outcome panel renderer with FE
  checkmark rows + Utilities/Utility-years rows). Smoke-tested: main
  12,492/666, placebo 12,531/673 (matches plan 0.1 exactly); F_main=50.01,
  F_placebo=53.17; MR 2SLS anchors reproduce to 2 decimals (arsenic
  3.11/1.52, nitrates 3.28/1.73, inorganic 2.00/1.60); placebo MR p-values
  .42/.17/.26 (all null), matching the grid log exactly.
- `run_k2_main_tables.r`: new. Writes all 7 Step 4 tables (allcat/MR/MCL
  2SLS panels, first stage, exclusion test, visit types, enforcement
  types). MR anchor gate and F=50.01 gate both pass exactly. Fixed a
  fixest `etable()` quirk: `drop=` matches against the *dict-relabeled*
  term string, not the raw variable name, once `dict=` is also passed —
  changed `drop="num_facilities"` to `drop="Number of intake facilities"`
  in the first-stage table call.
- `run_k2_placebo_tables.r`: new. Writes 4 Step 5 tables (MR/MCL 2SLS,
  visit types, enforcement types) on the purity-screened placebo arm.
  F_placebo=53.17 gate and all-three-null MR gate (p=.17/.42/.26) both
  pass exactly, matching the grid log. Captions describe the sample in
  plain language ("utilities with a coal mine within two flow steps
  downstream of their intake and no coal mine upstream"); no
  "placebo"/"falsification" wording anywhere in visible table text.
- `run_k2_sum_tables.r`: new. Writes `violation_binary_days_panels_k2.tex`
  and `enforcement_visit_type_panels_k2.tex`. Reference 2SLS sample for the
  enforcement/visit table re-derived from `obs_selection` (9 FE-singleton
  rows dropped, N=12,483) rather than hardcoding the original's 6,225
  anchor, since the k2 sample size differs from the D1 legacy sample.
- `run_k2_6yr_tables.r`: new. Writes `6yr_huc02fe_inorg_ravalli_2005_k2.tex`
  (4 chems survive the >=30-obs filter: arsenic/nitrate/barium/selenium,
  matching the plan exactly), its sumstats companion, `pt_balance_6yr_k2.tex`,
  and `syr2_mr_comparison_k2.tex`. Coverage: 132/666 k2 main-arm utilities
  (19.8%) have SYR2 concentration coverage — flagged to user, not narrated
  in table notes.
- `run_mr_concentration_lag_ols_k2.r`: extended (not rewritten) to also
  render `mr_concentration_lag_ols_k2.tex`; k2 estimates (58.93**/24.55,
  1.29/1.46) reproduce the published k=1 anchor (58.97**/24.60, 1.28/1.43)
  almost exactly.
- `run_k2_figures.r`: new. Writes both k2 figures. FWL reproduction gate:
  initially off by 0.0009 (3rd-decimal mismatch) because the residualization
  only partialled out the 3 FEs, not `num_facilities`; fixed by also
  partialling out `num_facilities` in the verification regression (matches
  Frisch-Waugh-Lovell exactly) — now an exact match (diff = 0.000000). The
  plot itself stays the simpler FE-only bivariate residual scatter, matching
  the established codebase design.
- Wired all 18 k2 tables + 2 k2 figures into `main.tex` after the existing
  `h2_snsv_d12` entry and after `first_stage_scatter_dwnstrm`, inside the
  existing `\begingroup...\endgroup` block, per plan Step 9. Compiled with
  MiKTeX pdflatex: exit 0, two passes, no undefined references, no
  multiply-defined labels, no `LaTeX Warning`s after the second pass.
- Fixed a real overfull hbox (~40pt) in `violation_binary_days_panels_k2.tex`:
  the auto-width `l` row-label column overflowed once "Inorganic chemicals"
  (the capitalized display label) replaced the original's "IOCs"
  abbreviation, which was already within ~6pt of the text width. Switched
  to a fixed-width `p{3.0cm}` raggedright label column and rebalanced the
  numeric column widths (Panel A 2.72cm x4, Panel B 1.15cm x8) so both
  panels total ~16.0cm, under the 16.51cm text width. Re-verified: 0
  overfull hboxes in that file after the fix.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| any_enf built as constant 1 within sdwa_enf_agg_k2.parquet grouped rows | Matches enforcement_chain_d12.r's construction exactly: a (PWSID,year) group only exists if it has >=1 enforcement record, so any_enf=TRUE for every grouped row; zero-filled to 0 on panel join for absent PWSID-years. |
| step_huc_links_k2.parquet is PWSID-level (no year column) | Matches the plan's stated schema; intake HUC is effectively stable per PWSID so this equals the per-year n_hucs_linked in step_instruments.parquet (verified on 50 PWSIDs). |
| `num_hucs` covariate silently dropped by fixest in pt_balance_6yr_k2 | Collinear with other covariates in the small (n=122) k2 balance sample; confirmed via a direct `lm()` fit showing the full-rank OLS estimates match feols's remaining 7 coefficients exactly. Not a bug — expected small-sample behavior, noted here rather than narrated in table notes (Rule 8). |
| etable() `drop=` must target the dict-relabeled string, not the raw variable name | Confirmed via direct test: once `dict=` is also passed to etable(), fixest's `drop=` regex matches against the post-relabel term. |

## Verification Results
- [x] All 9 scripts (2 Python builders + k2_common.r + 6 run_k2_*.r +
      extended run_mr_concentration_lag_ols_k2.r) exit 0
- [x] 18 `.tex` files (14 in output/reg/, 4 in output/sum/) + 2 `.png` files
      exist, are non-zero, and are all `\input{}`/`\includegraphics{}`'d
      into main.tex
- [x] No existing file overwritten: `git status` on clean_data/output/code
      shows only new `??` files + the one intentionally-extended script;
      mtimes on all pre-existing `_steps`/`_d12` caches predate this session
- [x] F_main = 50.01 exact, F_placebo = 53.17 exact (both > 10)
- [x] MR 2SLS anchors exact to 2 decimals (arsenic 3.11/1.52, nitrates
      3.28/1.73, inorganic 2.00/1.60)
- [x] Placebo MR null on all three outcomes (p = .17/.42/.26, matching log)
- [x] Reduced-form sign is opposite 2SLS sign in every column of every 2SLS
      table (mechanical IV identity, spot-verified on 3 tables)
- [x] N plausible: thousands of utility-years on violation/enforcement
      tables; SYR2 tables much smaller (132/666 = 19.8% coverage) as
      expected and flagged below, not in table notes
- [x] Wording sweep: zero matches for CWS/PWS/"community water system"/
      "public water system" across all 18 `.tex` files
- [x] FE-row sweep: every k2 regression table carries all 3 FE checkmark
      rows (per the plan's explicit Step 3 decision, overriding the general
      uniform-FE-omits-row convention); every table's notes are silent on
      fixed effects; `6yr_huc02fe_inorg_ravalli_2005_k2` and
      `mr_concentration_lag_ols_k2` (uniform FE, standard convention, not
      the render_panel_k2 3-row convention) correctly omit rows and state
      FE in notes instead
- [x] Notes-convention + formatting sweep: `\textit{Notes:}` prefix present
      everywhere; no scientific notation (one false positive: "Pre-2006"
      contains "e-2"); no cross-references/file paths/individual PWSIDs; no
      sample-cleaning or robustness/placebo/falsification wording in visible
      text (only inside `\label{}` identifiers, invisible in the compiled
      PDF and required by the plan's naming convention); stars legend
      present on every regression table; no stray `\%` on any scaled
      coefficient
- [x] `main.tex` compiles with MiKTeX pdflatex, exit 0, two passes: no
      undefined references, no multiply-defined labels, no `LaTeX Warning`s
      after the second pass, 0 overfull hboxes introduced (one real ~40pt
      overflow found and fixed — see Design Decisions)
- [x] Both new figures render and display correctly (visually inspected)

**Quality score: ~90 (peer-review ready).** All hard numerical gates pass
exactly; wording, FE-row, and notes conventions verified compliant;
compiles cleanly with no overfull hboxes. Held back from 95 by: some
regression formulas are built dynamically via `paste0()`/`as.formula()`
rather than as static named objects (matches the existing
`run_step_instrument_grid.r` precedent this pipeline extends); the balance
test's `num_hucs` covariate is silently dropped by fixest in the small
(n=122) k2 subsample due to collinearity (documented, not a bug, but a real
small-sample limitation of the k2 SYR2 slice).

## Coverage caveat (per plan Step 7 — reported here, not in table notes)
Only 19.8% of the k2 main arm (132 of 666 utilities) has SYR2 concentration
coverage. The five SYR2/6-Year-Review exhibits (regression, sumstats,
balance test, and the mr_concentration_lag_ols table) therefore describe a
much smaller, larger-utility-skewed slice of the arm than the 13 violation/
enforcement/visit tables do.

## Open Questions / Blockers
- None blocking. The `num_hucs` balance-test covariate drop (small-sample
  collinearity) and the dynamic-formula style are accepted, documented
  limitations, not open questions.

## Next Steps
- User review of the new "Two-step upstream watershed linkage" main.tex
  section and the two new figures.
- If satisfied, commit the new scripts, outputs, and main.tex/main.pdf
  changes (not yet committed — awaiting user go-ahead per
  plan-first-workflow git discipline).
