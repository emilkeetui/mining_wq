# Session: 2026-08-27 — Downstream-of-intake mines placebo plan

## Objective
Write an implementable plan (for a Sonnet model to execute) for a placebo/falsification
test using coal mines located one HUC12 **downstream of the CWS intake** as a placebo
treatment, instrumented by post95 x sulfur of those mine HUCs.

Plan saved to `~/.claude/plans/downstream-of-intake-mines-placebo-test.md`.

## Changes Made
- No code changes. Plan document only.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| New variable suffix `_downstream_intake` | `minehuc_downstream_of_mine` already means "CWS is downstream of mine" (treated). The placebo is the opposite direction (mine downstream of intake). Reusing existing names would cause silent wrong-column merges. |
| Placebo sample = CWSs upstream of a mine, excluding any with intakes in mine or downstream-of-mine HUCs | Gives a "pure" no-exposure sample; also makes the placebo and main samples disjoint, which licenses an independent two-sample z-test for the equivalence check. |
| Derive intake→downstream-mine linkage from the HUC shapefile `tohuc` network, not from existing `sulfur_upstream`/`tohuc` columns in `huc_coal_charac_geom_match.csv` | Those column semantics are ambiguous for `upstream_of_mine` rows; mirroring `build_2step_sample.py`'s shapefile-based D1→D2 pattern is verified-working. |
| Reduced form is the PRIMARY placebo test, 2SLS secondary | The exclusion restriction is a statement about the reduced form; the RF test does not require dividing by a possibly-small first stage. |
| Placebo first stage must still be STRONG | If the instrument does not move downstream-of-intake mine counts, a null RF is trivially expected and tests nothing. Strong F confirms the instrument has bite in this sample. |
| Equivalence test via two-sample z on disjoint samples | Converts "fail to reject zero" (absence of evidence) into "reject equality with the main estimate" (evidence of absence). |
| Weak-instrument threshold 23.11, not 10 | Montiel Olea & Pflueger (2013) Table 1, K_eff = 1, 5% test / 10% worst-case bias — correct for this just-identified, CWS-clustered design. Verified against the source PDF this session. |

## Verification Results
- [x] Plan written to disk
- [ ] Implementation not yet run (deferred to Sonnet implementer)

## Open Questions / Blockers
- Unknown whether the placebo sample will be large enough (>= 100 CWSs) or have enough
  sulfur variation. Plan includes an explicit gate to stop and report if not.
- Unknown whether the placebo first stage will be strong. Plan includes an interpretation
  table covering the weak-F case (test uninformative, must not be reported as a pass).

## Next Steps
- Hand plan to Sonnet implementer.
- Surface immediately if placebo 2SLS is positive/significant — that is a genuine
  exclusion-restriction problem, not a robustness footnote.
