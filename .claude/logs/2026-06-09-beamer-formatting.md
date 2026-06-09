# Session: 2026-06-09 — Beamer slide formatting

## Objective
Fix LaTeX/Beamer formatting issues in the dissertation chapter presentation.

## Changes Made
- No files edited; all fixes were provided as guidance to the user.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Use `split` inside `equation` for multi-line equations | Gives alignment control via `&`; works cleanly in beamer |
| `\setbeamertemplate{footline}` must come after `\usetheme` | Theme overwrites templates set before it |

## Fixes Provided
1. `\\` inside `equation` env — replaced with `split` environment for both 2nd-stage and 1st-stage 2SLS equations
2. Boadilla footer (author/title) — `\setbeamertemplate{footline}[page number]` must be placed after `\usetheme{Boadilla}`

## Verification Results
- [ ] User to verify footer fix after reordering preamble

## Open Questions / Blockers
- None

## Next Steps
- None pending; user-driven
