# Session: 2026-09-23 — k=2 regressor-swap robustness tables

## Objective
Re-estimate each k=2 table family with the other mining regressor (plan
`~/.claude/plans/k2-regressor-swap-robustness-tables.md`):
- violation/visit/enforcement 2SLS + first stage: mine count -> cumulative upstream production (10M ST)
- SYR2 concentration OLS: cumulative production -> contemporaneous upstream mine count
Outputs to `output/reg/` only; `main.tex` untouched.

## Changes Made
- Branch `k2-regressor-swap-robustness` (from `k2-updn-two-instruments`).
- `k2_common.r`: `f_clustered(..., endog=)` (default = mine count); `render_panel_k2` passes `coalvar` to the F helper; new `add_cum_prod_k2()`.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Skip `exclusion_test_num_facilities` swap | It never uses the mining regressor — a swapped version is identical |
| Cum. stock built on full main-arm k=2 si panel before screens | Stock starts in 1985, matches build_dose_sample() |

- New `run_k2_cumprod_tables.r` (6 tables + 6 _present), `run_k2_6yr_nmines_tables.r` (1 table + _present).

## Verification Results
- [x] run_k2_main_tables.r anchor gates pass (3.94/3.78/3.06, F=49.20); `_k2` outputs byte-identical (no git diff)
- [x] run_k2_cumprod_tables.r exit 0; 565 utilities / 10,641 obs in every column = parent N
- [x] run_k2_6yr_nmines_tables.r exit 0; 8 models; 1,716 rows identical to parent
- [x] No sci notation, Notes/stars present, no variable names; all 14 files compile in scratch wrapper (0 errors, 0 overfull)

## Key finding (cumprod tables)
- First stage FLIPS SIGN: instrument lowers mine count (-0.49***, F=49.2) but RAISES cumulative production (+0.073***, F=8.93 state x year; F=0.59 utility+year FE).
- RF identical to parent (e.g. MR nitrates -2.12), so 2SLS on violations turns large and negative (~-26 pp per 10M ST with state x year FE; ~-116 with year FE, F=0.59).
- Interpretation (unverified): after 1995, high-sulfur areas have fewer mines but not less output -- consistent with consolidation into fewer, larger mines. Per plan, spec not changed; reported to user.
- SYR2 mine-count table: only barium (one step) marginally significant (0.0035*); arsenic one-step coef displays as 0.0000 at 4 dp.

## Follow-up: switch to ANNUAL production (user decision)
- F-stat comparison (scratch): annual prod 1M ST F=18.05 (util+yr) / 11.79 (state x yr), coef -0.10; log1p F~40-44; any-prod F~36-40; cumulative 0.59/8.93.
- USER DECISION: use annual production instead of cumulative for the 2SLS tables; also add an annual-production version of the SYR2 table.
- `run_k2_cumprod_tables.r` -> renamed `run_k2_annprod_tables.r`; regressor `coal_prod_upstream_1mst` = production_linked_sum/1e6 (0 NAs on the sample); outputs `_k2annprod`. Deleted the superseded untracked `_k2cumprod` outputs.
- `k2_common.r`: removed now-unused `add_cum_prod_k2()`; added dict label "Upstream coal prod. (1M ST)".
- `run_k2_6yr_nmines_tables.r` -> renamed `run_k2_6yr_swap_tables.r`; writes both `_k2nmines` (byte-identical to before) and new `_k2annprod`.
- Bug caught: heredoc assembly halved backslashes in the new tail (`"\textit"` -> tab, `"\bottomrule"` -> backspace, silent in R). Fixed and diffed against source; the rendered .tex has no tab characters.
- Results: violation 2SLS positive again: any/MR +15 to +21 pp per 1M ST, significant in all 6 columns; MCL null. Visits: only inspection is significant (10.46*). Enforcement: formal (util+yr FE) -13.84***; others null.
- SYR2 annual: arsenic one step 0.0032***, nitrate one step 0.0790*, nitrate two steps 0.0610***; barium and selenium not significant.
- 16 files: format checks pass, compile 0 errors / 0 overfull.

## Open Questions / Blockers
- None. Minor: one MCL OLS cell displays "-0.00" (2 dp).

## Next Steps
- /commit on branch k2-regressor-swap-robustness.
