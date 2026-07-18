# Session: 2026-07-17 — Solve reporting–MCL model and unify with Theoretical Framework

## Objective
Solve the Kaplow–Shavell-style reporting/MCL model sketched in
`.claude/logs/optimal reporting with costly reporting.sty`, check whether
Propositions 1–3 of the Theoretical Framework section survive, and propose a
unified model replacing the black-box penalty schedule ε(k).

## Changes Made
- `optimal reporting with costly reporting.sty`: appended two sections —
  "Solution of the reporting–MCL model" (four-strategy solution, cutoff θ*,
  four reporting regimes) and "A unified model" (continuous negligence with
  endogenous penalty e(a) = N·min{c + r·q(a), pt + ps·q(a)}).

## Key Results
- Compliance cutoff: comply iff θ ≤ θ* = [min(c+r, p(s+t)) − min(c, pt)]/ā.
- Regime C (compliers report, violators hide) exists iff r > ps — the
  strategic-MR regime matching the project's empirical story; there θ*ā = p(s+t) − c.
- Props 1–2 hold only in extensive-margin/step form in the discrete model;
  Prop 3 holds in regimes A/B/C but can FAIL in regime D when pt > r.
- Unified model recovers all three propositions in piecewise-smooth form with
  an upward jump in a(θ) at the reporting threshold; adds MR-violation and
  selection-on-reporting predictions (measured MCL flat while true exceedances rise).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Effort cost θa (type restored to payoffs) | Sketch payoffs had no θ → all CWSs identical, no cross-section |
| a ∈ {0, ā} bang-bang in discrete model | Penalty depends only on binary MCL status |
| q(a) exceedance prob per event, N events | Nests Section 1 Poisson with intensity N·q(a) |

## Correction (user, same day)
[LEARN:mechanism] wrong: model framed MR violations as hiding MCL exceedances →
right: primary driver is mining raising TESTING COSTS c(m) with contamination
staying below MCL and sanctions fixed; hiding is secondary. Model reworked:
- Testing rule is now c ≤ ĉ(a) = pt − (r−ps)q(a), c ~ G(·;m) FOSD-increasing in m.
- Primary margin: clean systems (q≈0) stop testing when c > pt — MR with MCL=0.
- Secondary margin: ĉ decreasing in q → near/above-MCL systems exit testing first.
- Prop 2′ restated: MR(m) = E_θ[1 − G(ĉ(a(θ)); m)] increasing in m holding
  contamination fixed; β_MCL ≈ 0 because q small and exceeders exit reporting first.
- New lever result: monitoring sanction t raises ĉ by p per unit — the policy
  offset to mining-induced testing costs.
- Memory project_regulator_pivot.md updated with the mechanism correction.

## Open Questions
- Whether to fold the unified section into the paper's Theoretical Framework
  (would replace ε(k) with primitives c, r, s, t, p).
- Per-event cost shocks to smooth the all-or-nothing MR margin (noted as extension).
