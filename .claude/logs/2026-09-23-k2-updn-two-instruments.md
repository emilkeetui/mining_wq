# Session: 2026-09-23 — k2 upstream + downstream two-instrument 2SLS

## Objective
Add downstream coal mines (within 2 flow steps downstream of the intake) as a second
endogenous regressor, instrumented jointly with upstream mines by post95 × upstream
sulfur and post95 × downstream sulfur. Purpose: exclusion/exogeneity test — the
downstream 2SLS coefficient should be statistically zero if the instrument is valid.

Plan: `~/.claude/plans/k2-upstream-downstream-two-instrument-2sls.md`
Branch: `k2-updn-two-instruments`

## Changes Made
- `code/coal_mining_water_quality/run_k2_updn_tables.r` (new): builds panel, joins
  placebo-arm k=2 rows as downstream vars, gates, writes 7 tables × (+_present), all `_k2updn`.
- `k2_common.r`, `run_k2_main_tables.r`, existing `_k2` outputs untouched.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| SW F computed manually (2SLS of x1 on x2 with both z's, residual on z's, clustered Wald × 2) | fixest `kpr` fails on this design; `ivwald` not cluster-robust |
| Probe first-stage numbers printed, not hard-gated | sample identity is gated by the single-instrument anchor instead; they matched exactly anyway |
| `etable(..., replace = TRUE)` on fs table | avoid appending on reruns |

## Verification Results
- [x] Script runs end-to-end (exit 0, ~25 s)
- [x] 14 outputs exist in output/reg/
- [x] Anchor gate (3.94/3.78/3.06) PASSED; 565 utilities / 10,641 obs in every MR & enforcement column
- [x] Sulfur mirror gate PASSED both directions; join lost 0 rows / 0 utilities (574 pre-singleton)
- [x] First stage reproduces probe exactly: joint F 24.68/18.31 (state×yr), 19.95/17.50 (util+yr); SW F 4.03/3.79, 5.75/5.23
- [x] All 14 tables compile in scratch wrapper; no errors / overfull boxes; no sci notation
- Result: downstream 2SLS coefficient insignificant (p ≥ 0.1) in 29/29 columns, but CIs wide
  (e.g. MR inorganic state×yr 18.19, 95% CI −15.3 to 51.7). Upstream 2SLS loses significance everywhere.
- Note: OLS downstream mines coefficient IS significant in violation tables (e.g. MR nitrates 3.79***).

## Open Questions / Blockers
- Test has low power (SW F < 10 in every column); cannot rule out downstream effects of the size of the upstream effect.

## Next Steps
- User review; merge branch to master on approval. Writeup mirroring not in scope.

## Follow-up (same day): user asked to drop extra F tests, add tables to main.tex
- Removed Sanderson–Windmeijer F everywhere (fs_stats_updn, panel notes, fs table row/notes, summary).
  Kept one clustered first-stage F per instrumented variable (Wald F of both instruments):
  24.68 up / 18.31 down (state×yr); 19.95 / 17.50 (util+yr).
- Renderer: label col 7cm ragged-right, data cols 2cm — labels wrapped and 2-digit coefs overflowed in main.tex's font.
- fs table: `\par` inserted before notes group closes so `\raggedright` beats the float's `\centering`.
  NOTE: existing fs_dwnstrm_minevio_ivsum_k2 has the same centered-notes issue (not touched).
- main.tex: new `\subsection*{Upstream and downstream coal mines instrumented jointly}` after the k2placebo block,
  7 `\outreg{..._k2updn}` tables. latexmk: 91 pages, 0 errors, 0 undefined refs, 0 overfull boxes from new tables.
