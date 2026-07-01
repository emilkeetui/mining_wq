# Session: 2026-06-30 — Suppress constant in sanitary_visit_enforcement_iterative table

## Objective
Suppress the intercept/constant row from output/reg/sanitary_visit_enforcement_iterative.tex.

## Changes Made
- Attempted `drop = "Intercept"`, `drop = "^(Intercept)$"`, `drop = "\\(Intercept\\)"` — none suppressed the constant in etable output.
- Reverted: removed the `drop` argument entirely from the `etable()` call per user instruction. Table left as-is with the constant row present.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Leave constant in table | fixest::etable() `drop` argument does not reliably suppress `(Intercept)`; user chose to leave the table as-is rather than pursue a workaround |

## Verification Results
- [x] Script reverted to clean state (no drop argument)
- [x] Table regenerated successfully (exit 0, file non-zero)

## Open Questions
- How to suppress the constant in fixest etable when the no-FE spec includes one — `drop`, `keep`, and regex variants all failed.
