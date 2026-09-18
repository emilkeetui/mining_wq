# Session: 2026-09-17 — year / state×year FE checkmark fix (planning only)

## Objective
Go through all tables in `job_talk.tex` and fix any specification where a
standalone `year` fixed effect is shown as checked alongside an interacted
`STATE_CODE^year` (state × year) fixed effect — `year` is collinear with
(nested in) `STATE_CODE^year`, so `fixest::feols()` silently drops the
standalone term, but the table-building code was independently marking
"Year fixed effects" as checked for every column regardless of what was
actually estimated.

## Approach
Entered plan mode per `plan-first-workflow.md` (task modifies a regression
specification / table-generation code, touches 2+ files). Used an Explore
subagent, then verified its findings by directly reading the relevant source
(`k2_common.r` lines 255-434, `run_k2_main_tables.r` full file).

## Key Findings / Decisions
- Root cause: `k2_common.r` line 330 (`fe_row_year <- paste0("Year fixed
  effects & ", chk_all, ...)`) checks every column unconditionally instead of
  masking on whether that column's FE spec actually has a bare `year` term.
- 6 tables referenced by `job_talk.tex` are affected:
  `2sls_dwnstrm_minevio_allcat_ivsum_binvio_k2`,
  `2sls_dwnstrm_minevio_mr_ivsum_binvio_k2`,
  `2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2`, `h2_snsv_d12_k2`,
  `h3_inf_formal_d12_k2`, `exclusion_test_num_facilities_k2` — all produced by
  `code/coal_mining_water_quality/run_k2_main_tables.r` (sourcing
  `k2_common.r`).
- `6yr_huc02fe_inorg_ravalli_2005_k2` and `mr_concentration_lag_ols_k2`
  (also in job_talk.tex) are clean — no bare `year` + interacted-FE conflict.
- No `PWSID^year` (utility × year) interaction exists anywhere in this
  paper's tables — confirmed by grep — so only the `year`/`STATE_CODE^year`
  variant applies.
- User decision: also fix `fs_dwnstrm_minevio_ivsum_k2` (first-stage table,
  same script, same bug, but only referenced by `main.tex` not
  `job_talk.tex`) since it's the same script and low extra effort.
- User decision: proceed on top of existing uncommitted changes in the
  working tree (do not commit or stash first) — flagged per
  `data-safeguards.md` git discipline before starting.
- Numbers (coefficients/SEs/F-stats/N) are expected to be unchanged by the
  fix, since fixest already silently dropped the collinear term when
  fitting; only the displayed checkmark rows/lines change. This must be
  verified by diffing regenerated `.tex` output against the pre-fix version.
- Full plan (file-by-file edits, verification steps) saved to
  `C:\Users\ek559\.claude\plans\encapsulated-munching-hearth.md`.

## Verification Results
- [ ] Not yet executed — user approved the plan but asked for it to be
      executed in a separate window/session.

## Open Questions / Blockers
- None outstanding for the plan itself. Execution (edit `k2_common.r` /
  `run_k2_main_tables.r`, rerun script, diff outputs, recompile
  `job_talk.pdf`) is deferred to another session per user request.

## Next Steps
- In the executing session: follow `encapsulated-munching-hearth.md` step by
  step, including the anchor/gate `stopifnot()` re-checks and the
  post-fix diff confirming only FE-checkmark rows changed.
