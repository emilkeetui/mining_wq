# Session: 2026-08-27 — IV validation tests explainer

## Objective
User asked a conceptual econometrics question: what are the standard IV validation
tests (they recalled the weak-instrument test but not the others). No code or file
changes requested.

## Changes Made
- None. Conversational/explanatory response only.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Tailored answer to this project's IV setup | Instrument is `post95 × sulfur_unified`, just-identified, clustered SEs at PWSID — noted that Sargan/Hansen overid tests don't apply here, and that first-stage F should use Kleibergen-Paap/Montiel Olea-Pflueger given clustering |
| Tied exclusion-restriction discussion back to project's placebo strategy | CLAUDE.md already specifies temporal + geographic (upstream/downstream) placebos over deprecated chemical placebos (VOC/SOC/coliform) |

## Verification Results
- N/A — no code run, no output produced.

## Open Questions / Blockers
- None.

## Next Steps
- None pending from this exchange.
