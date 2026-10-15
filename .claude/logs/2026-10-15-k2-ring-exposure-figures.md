# Session: 2026-10-15 — k2 ring-exposure coefficient figures

## Objective
Replace step2/step23 sample tables with coefficient plots on the unchanged k2 sample, varying only exposure (k2, ring 2, ring 2-3). Plan: ~/.claude/plans/k2-ring-exposure-coef-figures.md

## Changes Made
- code/.../run_k2_ring_coefs.r: estimates 54 coefs -> clean_data/cws_data/k2_ring_coefs.parquet
- code/.../plot_k2_ring_coefs.r: 3 PNGs in output/fig/
- main.tex: step23 subsection replaced with 3 figures

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Branch k2-ring-exposure-figures off step2-sample-tables | CLAUDE.md branch suggestion; untracked step2 files left uncommitted (not asked) |
| Sample N = 10,641 / 565 utilities (not 10,650/574 in plan) | matches existing k2 tables' N; anchor gates pass |
| SYR2 figure uses facet_wrap free_x, strips left | arsenic/selenium CIs ~1% of nitrate range |
| Series offsets via manual y values | position_dodge unreliable horizontally |

## Verification Results
- [x] Estimation exits 0, 54 rows, anchors match k2 tables, all first-stage F > 10 (k2 49.2, ring2 30.5, ring23 27.4)
- [x] 3 PNGs inspected
- [ ] main.tex compile (running)

## Next Steps
- Commit after user confirms (no LaTeX build artifacts)
