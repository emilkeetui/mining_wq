# Session: 2026-05-25 — Navarro JMP firm data question

## Objective
Answer user's question: what firm data does navarro_jmp.pdf use to estimate the firm's structural model.

## Findings
Read pp.1-5, 14-20 of `.claude/skills/navarro_jmp.pdf`. Supply-side estimation uses:
- DTPM GPS panel (Aug 2022–Aug 2023, 30-sec pings) → frequency and headway regularity at route-day level (549k obs); also route length, speed, depot, bundle assignment.
- Contract/tendering data from DTPM: per-passenger price, per-km bids, fleet size, quality targets, penalty formulas, 2022 reform reassignment of routes to bundles.
- Smart-card tap-in data: route-level boardings in 30-min intervals (~3.5M trips/weekday).
- No accounting/balance-sheet data; cost parameters identified via firms' FOCs using reform-induced variation.

## Open Questions
None — single Q&A turn.

## Next Steps
None scheduled.
