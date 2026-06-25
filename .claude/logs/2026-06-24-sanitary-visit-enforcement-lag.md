# Session: 2026-06-24 — Sanitary visit / enforcement lag (Q1, Q2)

## Objective
Test whether sanitary visits play an informational role between CWSs and the regulator,
via two directional lagged regressions on the downstream 2SLS sample (349 CWSs,
PWSID x month panel, 1985-01 to 2005-12).

## Script
`code/coal_mining_water_quality/sanitary_visit_enforcement_lag.r`
Outputs: `output/reg/sanitary_visit_to_enforcement.tex`, `output/reg/mr_to_sanitary_visit.tex`

## Q1 — Does a sanitary visit predict enforcement in the next 6/12 months?
LPM, PWSID + month_idx FE, SE clustered by PWSID. Two visit definitions tested
(visit_san = SNSV/SNSP/SSVF; visit_any = any visit except FENF/IENF), four enforcement
categories (Informal, Resolving, Formal, Any).

**Panel A (visit_san):**
| Outcome | 6mo coef | base rate | 12mo coef | base rate |
|---|---|---|---|---|
| Informal | 0.0246** (0.0108) | 9.87% | 0.0138 (0.0129) | 16.06% |
| Resolving | 0.0057 (0.0073) | 6.70% | -0.0043 (0.0101) | 11.31% |
| Formal | 0.0026 (0.0038) | 1.17% | -0.0035 (0.0038) | 1.87% |
| Any | 0.0230** (0.0112) | 12.04% | 0.0108 (0.0132) | 18.75% |

**Panel B (visit_any):** same pattern, weaker — only Any@6mo significant at 10%
(0.0172*), Informal/Resolving/Formal all insignificant at both horizons.

**Takeaway:** sanitary visits raise the probability of informal enforcement and any
enforcement within 6 months (~2.3pp on a ~10-12% base), but the effect does not persist
to 12 months and never shows up for Formal enforcement (too rare, N=235 PWSID-months).

## Q2 — Does an MR violation predict a sanitary visit in the next 6/12 months?
Regressor redefined mid-session from IOC-MR only (RULE_CODE in {331,332,333}, 316
PWSID-months / 140 CWSs) to **any MR violation** (VIOLATION_CATEGORY_CODE=="MR", any
rule code, 1,789 PWSID-months / 250 CWSs) — IOC-only was underpowered.

| Outcome | 6mo coef | base rate | 12mo coef | base rate |
|---|---|---|---|---|
| Sanitary visit | 0.0096 (0.0092) | 6.65% | 0.0352** (0.0151) | 12.08% |
| Any visit | 0.0118 (0.0092) | 9.75% | 0.0367** (0.0150) | 16.27% |

**Takeaway:** no detectable effect at 6 months, but an MR violation raises the
probability of a sanitary visit within 12 months by ~3.5-3.7pp on a 12-16% base
(significant at 5%) — roughly a 25-30% relative increase over baseline.

## Combined interpretation
Q1 + Q2 together are consistent with a two-way information channel: CWSs that get
visited are somewhat more likely to face enforcement soon after (within 6mo, informal/
any only), and CWSs that rack up MR violations are more likely to get visited within
the following year. Effects are modest in absolute size and concentrated in different
horizons (Q1 short-run, Q2 longer-run), so the visit-enforcement link looks more
immediate/operational while the violation-visit link looks more like an annual review
cycle.

## Next step (separate session)
User is switching to an Opus model to use these Q1/Q2 estimates to adapt a regulator-CWS
model in which sanitary visits are the mechanism for gathering information that feeds
into enforcement decisions (companion to the K&S 2019 critique — `h(a)` is no longer
treated as a primitive the regulator observes for free).
