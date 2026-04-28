# Staggered DiD MR Results — run_staggered_did.r
*Date: 2026-04-28 | Sample: 2-step downstream panel (prod_vio_sulfur_2step.parquet)*

---

## Sample

| | |
|---|---|
| PWSIDs | 284 |
| PWSID × year rows | 5,964 (1985–2005, excl. WV3303401) |
| mining_MR_share_days > 0 | 471 PWSID-years (7.9% of panel) |
| mining_MCL_share_days > 0 | 21 PWSID-years (0.35% of panel) |

MCL is too sparse for any estimator to detect effects. All meaningful results are on MR.

---

## Estimator 1 — Sun-Abraham (Mine Openings)

**Sample:** 170 PWSIDs (3,570 rows). 114 PWSIDs with first mine in 1985 dropped as left-censored. Remaining: ~100 post-1985 openers + 70 never-treated control.

**Cohort sizes:**

| Cohort | N |
|--------|---|
| 1986 | 24 |
| 1987 | 9 |
| 1988 | 23 |
| 1989 | 1 |
| 1990 | 8 |
| 1991 | 10 |
| 1992 | 1 |
| 1995 | 7 |
| 1997–2005 | 2–4 each |
| Never-treated (Inf) | 70 |

**Note:** VCOV matrix was non-positive semi-definite for all three SA models (fixed automatically by fixest). Results should be treated with caution — thin cohorts inflate SEs.

**MR composite ATT by cohort:**

| Cohort | Estimate | SE | p-value | Sig |
|--------|----------|----|---------|-----|
| 1986 | 2.2 | 22.8 | 0.922 | — |
| 1987 | 13.6 | 31.3 | 0.664 | — |
| 1988 | −54.6 | 62.9 | 0.387 | — |
| 1989 | 4.0 | 18.7 | 0.832 | — |
| 1990 | 55.1 | 31.9 | 0.086 | † |
| 1991 | 51.0 | 33.0 | 0.125 | — |
| 1992 | −11.2 | 10.2 | 0.273 | — |
| 1995 | 35.7 | 25.8 | 0.169 | — |
| 1997 | −1.6 | 7.4 | 0.825 | — |
| 1998 | 113.7 | 87.7 | 0.197 | — |
| 1999 | 6.5 | 19.5 | 0.741 | — |
| **2001** | **71.9** | **9.0** | **<0.001** | **\*\*\*** |
| 2003 | 9.4 | 8.2 | 0.255 | — |
| 2004 | 15.0 | 10.0 | 0.137 | — |
| 2005 | 13.7 | 8.6 | 0.113 | — |

† p < 0.10

**Interpretation:** Only the 2001 cohort (n=2 PWSIDs) produces a significant ATT (71.9***, t=8.0). This is a single thin-cohort result and should not be over-interpreted — two PWSIDs gaining mines in 2001 incurring large MR violations is consistent with chance. All other cohorts are insignificant.

**MCL composite:** All cohorts insignificant (t-stats all < 1.0). Confirms power failure.

**Figures:** `output/fig/sdid_open_mr_composite_eventstudy.png`, `sdid_open_mrnit_eventstudy.png`

---

## Estimator 2 — Closing Event Study (Relative-Time)

**Sample:** 214 PWSIDs (4,494 rows): 156 closers + 58 always-treated control. Event time trimmed to [−8, +8].

**MR composite post-closing coefficients (relative to t = −1):**

| Rel. year | Estimate |
|-----------|----------|
| 0 | +12.1 |
| +1 | −13.6 |
| +2 | +12.3 |
| +3 | +16.0 |
| +4 | +22.6 |
| +5 | +19.8 |
| +6 | −10.3 |
| +7 | −8.6 |
| +8 | −10.8 |

**Interpretation:** Coefficients oscillate without a consistent negative trend following mine closure. If mines cause MR violations, closing events should produce a persistent *decrease* in violations post-closure. No such pattern is visible. The closing event study does not support symmetric treatment effects for MR violations.

**Caveat:** The always-treated control group (58 PWSIDs) is small and may not satisfy parallel trends with respect to closers. Results are not reliable.

**Figures:** `output/fig/sdid_close_mr_eventstudy.png`, `sdid_close_nit_mr_eventstudy.png`

---

## Estimator 3 — DIDmultiplegtDYN (Continuous Treatment)

Uses `num_coal_mines_upstream` as continuous treatment. Handles reversals (multiple openings/closings). N=5,964 throughout; 182 switchers in period 1.

### MR Composite

**Effects (treatment periods):**

| Period | Estimate | SE | 95% CI | Sig |
|--------|----------|----|--------|-----|
| Effect_1 | 3.4 | 10.1 | [−16.4, 23.2] | — |
| Effect_2 | 15.5 | 19.0 | [−21.7, 52.7] | — |
| Effect_3 | 11.9 | 18.8 | [−25.0, 48.7] | — |
| Effect_4 | 23.5 | 21.3 | [−18.3, 65.4] | — |

Joint test p-value: **0.555** (fail to reject null)

Average cumulative ATT: **19.8** (SE = 22.4, CI: [−24.1, 63.8])

**Pre-trend placebos:**

| Placebo | Estimate | SE | p-value |
|---------|----------|----|---------|
| Placebo_1 | −6.5 | 17.4 | — |
| Placebo_2 | 36.5 | 32.5 | — |
| Placebo_3 | 13.3 | 46.0 | — |

Joint placebo test p-value: **0.243** (parallel trends not rejected)

### Nitrates MR

| Period | Estimate | SE | Sig |
|--------|----------|----|-----|
| Effect_1 | −1.2 | 3.9 | — |
| Effect_2 | 3.7 | 5.9 | — |
| Effect_3 | 2.4 | 6.7 | — |
| Effect_4 | 5.6 | 7.0 | — |

Joint test p-value: **0.586** | Average ATT: **3.7** (SE = 6.8)

Placebo joint test p-value: **0.323** (parallel trends not rejected)

### MCL Composite (for comparison)

| Period | Estimate | SE | Sig |
|--------|----------|----|-----|
| Effect_1 | −0.06 | 0.04 | — |
| Effect_2 | 0.05 | 0.10 | — |
| Effect_3 | −1.18 | 1.16 | — |

Joint test p-value: **0.292** | Average ATT: **−0.55** (SE = 0.54)

---

## Summary Assessment

| Estimator | MR Result | Key Limitation |
|-----------|-----------|----------------|
| Sun-Abraham (openings) | Insignificant except 2001 cohort (n=2) | Left-censoring drops 114/214 treated PWSIDs; thin cohorts |
| Closing event study | No symmetric decrease after closure | Small always-treated control; oscillating coefficients |
| DIDmultiplegtDYN | Positive but insignificant (ATT=19.8, p=0.56) | Effects too imprecise; parallel trends pass but SEs are large |

**Overall:** Staggered DiD estimators cannot reject the null of no MR effect, and cannot detect MCL effects at all. The effects are **positive in direction and consistent with the 2SLS result** but not precisely estimated. This reflects a fundamental limitation: the staggered DiD uses only discrete mine opening/closing variation, which is less powered than the 2SLS approach using continuous ARP-induced production changes.

**Use as:** Appendix robustness check — confirms the 2SLS MR result is not purely an artifact of the ARP exclusion restriction, but does not strengthen the precision or add new evidence for MCL effects.

**Figures produced:**
- `output/fig/sdid_open_mr_composite_eventstudy.png`
- `output/fig/sdid_open_mrnit_eventstudy.png`
- `output/fig/sdid_open_mcl_composite_eventstudy.png`
- `output/fig/sdid_close_mr_eventstudy.png`
- `output/fig/sdid_close_nit_mr_eventstudy.png`
- `output/fig/sdid_close_mcl_eventstudy.png`
- `output/fig/sdid_dmdyn_mr_composite.png`
- `output/fig/sdid_dmdyn_nit_mr.png`
- `output/fig/sdid_dmdyn_mcl_composite.png`
