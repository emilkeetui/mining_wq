# Session: 2026-05-28 — Econometrics Q&A

## Objective
Answer conceptual econometrics questions (no code changes this session).

## Topics Covered
- Random effects regression: partial demeaning, GLS, Hausman test, contrast with FE
- Including time-invariant variables in 2SLS/FE: w_i × post95 as control for differential trends; HT estimator; Mundlak CRE
- Heterogeneous treatment effects in 2SLS: interacting endogenous variable with surface water dummy requires two endogenous regressors (mines, mines×surface) instrumented by (sulfur×post95, sulfur×post95×surface) simultaneously in feols

## Changes Made
- None

## Open Questions
- Whether to implement surface water heterogeneity table in didhet.r
