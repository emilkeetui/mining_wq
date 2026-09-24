# Session: 2026-09-24 — k2 accident instrument, progressive 2SLS

## Objective
Instrument annual upstream/downstream coal production (k=2) with Part 50 accident-report counts
plus post95 x sulfur, adding instruments progressively (up acc -> + z_up -> + dn prod via dn acc -> + z_dn),
for MR violations, enforcement, visits. State x year FE only. Stable k2 sample (565 / 10,641).
Plan: `~/.claude/plans/k2-accident-instrument-progressive-2sls.md`.

## Changes Made
- Git: committed msha-accident-build WIP (hook Option B, RAW_DIR fix, log) as fb0b8ff; stashed hook counters;
  branched `k2-accident-iv` off `k2-updn-annprod` and merged msha-accident-build (clean).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| One table per family, outcome x 4 spec columns | user choice |
| Panels: 2SLS + first stage with clustered joint F | user choice |
| Accident measure = all Part 50 report records | user choice |
| Commit message via file, not heredoc | hook false positive on the string raw_data in a redirect |

| Accidents in units of 10 reports | per-report first-stage coef ~0.012 would print as 0.01; per 10 = 0.12 (0.01) |
| Column widths 5.8cm label / 1.7cm data (was 7 / ~2.1) | first render over-shrunk the 12-col tables |

## Verification Results
- [x] Script runs end-to-end (exit 0, ~19 s)
- [x] 6 outputs in output/reg/ (*_k2accprog{,_present}.tex); no scientific notation
- [x] Anchor gate (19.39/18.58/15.02) + stable-sample gate (565 / 10,641) pass in all 44 columns
- [x] Test doc with booktabs/array/adjustbox/caption compiles, no errors / overfull boxes
- Quality score: 85

## Results (state x year FE)
- First stage: upstream accidents strongly predict upstream production, +0.12M ST per 10 reports (SE 0.01), F = 77.0 (spec 1).
  F upstream: 77.0 -> 57.0 -> 40.0 -> 31.6. F downstream: 11.2 (spec 3) -> 8.5 (spec 4, < 10).
- Upstream 2SLS on MR collapses toward zero with accidents: IOC -1.11 (1.50) spec 1, -0.47 (1.57) spec 4,
  vs 15.02 (8.99) with the sulfur-only single IV. Nitrates/arsenic similar. Not the "strongly negative"
  stop condition, but the accident-driven LATE clearly differs from the sulfur-driven one.
- Downstream 2SLS: n.s. for MR and enforcement. Significant for inspection visits (5.01 (1.98) spec 3,
  4.56 (1.88) spec 4) and enforcement visits at 10% in spec 4.
- The 20-column visit table is barely legible in portrait (adjustbox scale ~0.45).

## Open Questions / Blockers
- Accidents scale mechanically with mining activity (more hours -> more reports), so the accident-based
  estimate may identify off different variation than ARP. An over-identification test (spec 2) could help.
- Visit table layout: split into two tables, or landscape?

## Next Steps
- User review; optionally slides / main.tex backup links.
