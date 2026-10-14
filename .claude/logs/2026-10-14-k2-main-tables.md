# Session: 2026-10-14 — k2-main-tables-swap

## Objective
Promote Sample B (two-step upstream, `_k2`) tables/figures to the main exhibits in main.tex, replacing Sample A. SYR2 concentration table switched to annual production, two panels (A = Sample A utilities, B = Sample B). Plan: `~/.claude/plans/k2-main-tables-swap.md` (renamed from concurrent-noodling-squirrel.md).

## Changes Made
- Git: committed WIP on `scaled-mines-vs-production` (95c95e7; hook counters and texput.log left out), created branch `k2-main-tables`.
- `code/coal_mining_water_quality/run_k2_6yr_annprod_ab.r` (new): writes `output/reg/6yr_huc02fe_inorg_ravalli_2005_annprod_ab.tex` + `_present.tex`. Panel A N = 334/432/322/319 (1,558 rows, 122 utilities); Panel B N = 366/472/353/350. Panel B coefficients identical to Panel B of `..._k2annprod.tex` (verified).
- `code/coal_mining_water_quality/regen_sulfur_histogram_k2.r` (new): writes `output/fig/sulfur_histogram_k2.png` (238 linked mine HUC12s active 1985-2005).
- `main.tex`: end-matter tables now the k2 versions in the former Sample A order; "Two-step upstream watershed linkage" subsection removed (incl. cumulative `..._k2` SYR2 table); remaining scaled/placebo tables under new subsection "Coal mines downstream of the utility intake"; figures swapped to k2 (sulfur histogram, scatter, first-stage scatter); all body `\ref`s repointed to k2 labels (incl. line ~397 -> `..._annprod_ab`).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Keep Observations row in both panels | Panels have different N |
| Panel A uses annual (not cumulative) one-step production, Sample A rows | User-confirmed in plan |
| Figure captions: only histogram caption sample phrase changed; first-stage scatter caption sample/FE sentences NOT yet rewritten | see open questions |

## Verification Results
- [x] Both new scripts exit 0; outputs exist
- [x] Panel B matches existing k2annprod Panel B
- [x] No non-k2 `\outreg`/`\outsum` left in the end-matter; no live `\ref` without a `\label`
- [x] Full compile (latexmk, clean copy outside the source dir to avoid the stale ignored main.aux): no LaTeX errors, no `Not in outer par mode`, no undefined refs, no `??` in the PDF
- The three labels the user flagged (`tab:mr_mcl_violation_breakdown`, `tab:enf_action_type_ioc_dwnstrm`, `tab:sanitary_visit_timing_formal_enforcement_rate`) occur only in commented-out lines (315, 321, 495) — unchanged, not live.

## Prose numbers that no longer match (NOT rewritten; line numbers in main.tex)
Quoted value -> k2 value:
- First stage F (line ~430): 27.52 -> 49.20
- Obs in SYR2 paragraph (~397): "319 to 432" -> Panel A 319–432, Panel B 350–472
- SYR2 regression paragraphs (~397–407): all describe CUMULATIVE production (0.0023 arsenic per 10M ST, 79%, 0.0171 barium, 0.0033 selenium, 0.057 nitrate, 743M ST, 4.4M avg). The table now reports ANNUAL production per 1M ST (Panel A arsenic 0.0034***, nitrate 0.0748*, barium 0.0088, selenium 0.0018; Panel B arsenic 0.0004, nitrate 0.0610***, barium 0.0137, selenium 0.0004). Eq. `eq:huc02reg` and its variable definition (cumulative sum) also no longer match the table.
- OLS (~469): "1.7 to 1.9 pp" -> allcat k2 OLS ≈ 0.4–0.7 pp
- IV all categories (~470): 9.9 / 7.5 / 6.3 pp -> k2 IV ≈ 3.9–5.1 pp (significance levels change)
- MR IV (~477): 9.9 / 7.4 / 7.1 pp -> ≈ 3.8–5.1 pp; "same magnitude as combined" and "more than twice as likely" need re-checking
- MCL (~479): -0.02 and -0.8 pp -> k2 MCL estimates ≈ -0.1 to +0.2 pp
- Sanitary visit (~489): 14 pp, 100% -> k2 IV differs (≈0.8–1.1 in table units; check scaling); enforcement visits 3.7 pp, 300%
- Formal enforcement (~491): -5.7 pp, ">150% of baseline" -> k2 ≈ -3.1 to -3.4 pp
- Violation rates (~478): 4.0 / 6.1 / 4.6 pct; MCL count 26; MR counts 250–377; enforcement 21/19/3.5 pct; 71/65 pct; visit rates 14/4 pct; SYR2 t-test 18–23 pp; nitrate lag 59/26 pp: all come from Sample A summary tables, recheck against `_k2` versions
- Data section sample description (~line 10–13 of block: "directly downstream", "at least one intake in a HUC12 directly downstream"; histogram text "HUC12s where a utility intake and coal production are located", "0–4.5 percent", "slightly more than half low sulfur") -> now two flow steps upstream; histogram is the k2 HUC set
- Population exposed 1.3M (1985) -> 0.2M (2005) and the population-circle figure caption are unchanged (that figure was not swapped)
- Equation text defining first stage as "directly upstream" mines -> two flow steps

## Open Questions / Blockers
- First-stage scatter caption updated to k2 sample and utility, year, state x year FE.
- Scatter caption not yet checked against the k2 HUC set.
- Body prose rewrite (list above) left to user.
- Not committed: this branch's changes (new scripts, outputs, main.tex, session log) are uncommitted.

## Next Steps
- Rewrite prose above; decide on equation `eq:huc02reg`.
- Commit on `k2-main-tables`, merge to master after review.
