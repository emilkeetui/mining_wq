# Session: 2026-10-20 — high-low sulfur event study

## Objective
Binary high/low upstream-sulfur pre-trend check (raw means + event studies) on k2 main sample. Plan: ~/.claude/plans/high-low-sulfur-event-study.md

## Changes Made
- code/coal_mining_water_quality/run_k2_event_study_highlow.r: new script (branch es-highlow-sulfur, user-approved at Step 0)

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| New branch es-highlow-sulfur from HEAD; hook counter/texput.log left uncommitted | user choice |

## Verification Results
- [ ] Script runs end-to-end
- [ ] Output exists at expected path
- [ ] Row counts plausible

## Open Questions / Blockers
-

## Next Steps
-

## Results (main variant, state x year FE; high - low sulfur)
- First stage (mines): pre F=10.91 p<0.01, 1985-92 p<0.01, slope -0.12 (0.02), post-pre -0.89 (0.14). Mines already diverging before 1995 (declining diff).
- IOC MR: F=3.11 p=0.001, 1985-92 p=0.001, slope 0.29 (0.40), post-pre -2.96 (1.53). Nitrates/arsenic MR also reject (p<0.01). Driven by 1988-91 hump (not 1993 alone, not linear slope).
- Sanitary visit: p=0.044, 1985-92 p=0.24 (1993 driven). Informal enf: p=0.039, 1985-92 p=0.035. Inspection/enf visit/tech/smpl/formal: no rejection.
- Robustness nozero/tercile: same pattern. N: main 10,641; nozero 8,096; tercile 7,278.
- Pooled binary RF sign differs from post-pre only for any_snsv (both ~0).
## Decisions
- Parent N now parsed from table notes ("Number of observations"); original rf script's Observations-row parse would fail on current parent tex (not edited).
- Joint F uses rank-aware pseudo-inverse (nozero sample had singular early-year vcov).

## Correction (user): high sulfur = upstream sulfur >= 1.5% (paper definition, didhet.r:70), not the median
- Main split now 400 low / 174 high. Results below supersede the median-split numbers above: MR IOC pre F=2.78 p=0.003, 1985-92 p=0.003; first stage pre p<0.01, post-pre -1.34 (0.17); sanitary visit p<0.01 (1985-92 p<0.01); informal p<0.01; inspection/enf visit/tech/smpl/formal flat.

## 2026-10-21 — means figures: dropped "Change since 1994" row
- run_k2_event_study_highlow.r: removed the 1994-baseline row from means_df()/means_plot() (now facet_wrap, 1 row, height 3.2); added `--means-only` flag (skips overwrite guard, stops after Figure A) so es_highlow_* outputs are untouched.
- Regenerated means_highlow_{firststage,mr,visit,enf}_k2.png; updated the four \fignotes in job_app_jmp.tex (Figs 22-25); recompiled PDF (0 undefined refs, numbering unchanged).
- Old PNGs backed up in session scratchpad. Not committed.
