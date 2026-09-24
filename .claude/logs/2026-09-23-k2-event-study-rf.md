# Session: 2026-09-23 — k2 event-study reduced form

## Objective
Event-study RF (year × sulfur_mean0, ref 1994) for the 17 outcomes of the five main-arm k2 tables; pre-1995 joint Wald test as parallel-trends evidence. Plan: `~/.claude/plans/stateful-churning-unicorn.md`.

## Changes Made
- Committed prior branch work as d8b086e on `k2-regressor-swap-robustness` (k2_common.r edit, annprod + 6yr-swap scripts, their outputs, log). main.pdf and hook counters left uncommitted.
- New branch `k2-event-study-rf`; new script `code/coal_mining_water_quality/run_k2_event_study_rf.r`.
- Outputs: 6 PNGs `output/fig/es_rf_*_k2.png`; `output/reg/es_rf_pretrend_k2(.tex,_present.tex)`; `output/reg/es_rf_coefs_{allcat,mr,mcl,h2,h3}_k2.tex`.

## Design Decisions
| Decision | Rationale |
|---|---|
| Post − pre contrast averages pre over 1985–1994 with 1994 = 0 | exact event-study analogue of pooled post95 × sulfur term |
| Pre-trend F computed explicitly (b'V⁻¹b/q, df2 = fixest t-dof) | same as fixest::wald, but term set is asserted |
| h2 appendix table has no FE rows; FE stated in notes | single FE spec → Rule 7 |
| p-value moved into facet strip | geom_text annotation overlapped 1994/95 line and CIs |

## Verification Results
- [x] Exits 0; gates pass: sulfur time-invariant, years 1985–2005, pooled RF −1.51 (0.79) N=10,641 reproduced, all 29 ES models N=10,641
- [x] MR inorganic post−pre −1.49 (0.79) ≈ pooled RF −1.51
- [x] Scratch LaTeX compile of all 7 tex files: no errors / overfull boxes; no e± notation

## Key finding (flagged to user)
Pre-trend rejected (p<0.10) for all 3 any-category and all 3 MR violation outcomes, sanitary visits, informal enforcement, and no-enforcement. MR pattern: hump in 1988–1991 (~+6–7 pp) returning to ~0 by 1992–1994; post-1995 coefficients sit flat ~+2. The negative pooled RF is therefore driven by the pre-period hump, not a post-1995 drop. MCL outcomes and formal enforcement have clean pre-trends (p ≥ 0.59) but post−pre ≈ 0.

## Next Steps
- Decide how to handle the MR pre-trend (e.g., investigate 1988–91 hump: reporting-rule rollout / state data coverage).
- Tables not added to main.tex; branch not committed yet.

## Follow-up: job_talk_robustness.tex (new beamer deck)
- Copy of job_talk.tex in writeup/…/; job_talk.tex untouched.
- Main body, after "Instrument validity": two-instrument design, joint first stage (_k2updn), MR 2SLS (_k2updn), event-study design, headline ES figure, pre-trend table.
- k-grid radius robustness slides (fs, syr2, mr-down, enf, visit) replaced by regressor-swap slides (_k2annprod, 6yr _k2nmines); main-slide backlinks repointed. k-grid upstream-of-mine exclusion placebos kept (validity, not robustness).
- Appendix: remaining _k2updn tables (allcat, mcl, h2, h3, num_facilities) and ES figures (mr, allcat, mcl, h2, h3).
- latexmk: 73 pages, 0 errors; only overfull boxes are the 3 inherited from job_talk.tex. Pre-trend table slide renders very small (34-row table).
- Pre-trend table split for slides: run_k2_event_study_rf.r refactored into build_summ_tab(fams); new es_rf_pretrend_{vio,visenf}_k2_present.tex (panels re-lettered from A). Rerun exit 0, all gates pass, all 19 prior es_rf outputs byte-identical (md5). Deck now 74 pages, 0 errors, no new overfull boxes. What-I-find/conclusion left unchanged per user.
