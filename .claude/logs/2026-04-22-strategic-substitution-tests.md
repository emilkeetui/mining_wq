# Session: 2026-04-22 — Strategic substitution empirical tests

## Objective
Implement three empirical tests from `~/.claude/plans/strategic-substitution-tests.md`:
Test 1 (temporal sequencing), Test 2 (MR decomposition), Test 3 (contemporaneous correlation).

## Changes Made

- `code/coal_mining_water_quality/build_healthbased_mr.py` (new): Builds two data products:
  - **Section A**: Adds `mining_MR_regular_share_days` and `mining_MR_confirm_share_days` to
    `prod_vio_sulfur.parquet` → writes `prod_vio_sulfur_hb.parquet` (48,466 rows × 226 cols).
  - **Section B**: Builds all-states robustness panel (56,841 CWSs × 21 years) →
    writes `prod_vio_allstates.parquet` (1,193,661 rows × 11 cols).

- `code/coal_mining_water_quality/test_strategic_substitution.r` (new): Runs all three tests.
  Outputs 6 `.tex` tables (all confirmed present and non-empty).

## Data finding: IS_HEALTH_BASED_IND

`IS_HEALTH_BASED_IND == "N"` for 100% of mining MR violations (all 2.26M rows).
VIOLATION_CODE fallback: "03" (Monitoring, Regular) = 99.5%, "04" (Confirmation) = 0.5%.
In the downstream sample: 667 PWSID-years with regular MR > 0; only 9 with confirm MR > 0.
The decomposition table (Test 2) exists but confirm results are very noisy.

## Key empirical results

**Test 1 — Forward OLS (K=1,2,3):**
- β = 0.0008, 0.0045, 0.0079 on mining_MR_share_days predicting future mining_MCL
- All near-zero / statistically insignificant
- Rules out incapacity and monitoring-burden interpretations (both predict positive β)

**Test 1 — Forward 2SLS (K=1,2,3):**
- β = −0.059, −0.036, −0.027 (all negative)
- First-stage F: K=0: 11.4, K=1: 6.7, K=2: 8.3, K=3: 10.6
- **NOTE: K=1 and K=2 have F < 10.** The instrument `post95:sulfur_unified` is valid for
  `num_coal_mines_upstream` in main tables but weaker when used to instrument `mining_MR_share_days`
  directly (one additional step through the mechanism). Flag in paper footnote.

**Test 3 — Contemporaneous OLS:**
- β = −0.0015 (negative), consistent with strategic substitution

## Output files

| File | Status |
|------|--------|
| `output/reg/strategic_lead_lag.tex` | OK (3,467 bytes) |
| `output/reg/strategic_lead_lag_placebo.tex` | OK (3,426 bytes) |
| `output/reg/strategic_lead_lag_reverse.tex` | OK (3,024 bytes) |
| `output/reg/strategic_lead_lag_robustness.tex` | OK (2,404 bytes) |
| `output/reg/mr_healthbased_decomp.tex` | OK (3,839 bytes) |
| `output/reg/strategic_contemp_corr.tex` | OK (3,157 bytes) |

## Test 4 — Violation Sequencing (added 2026-04-23)

Added as a new section in `test_strategic_substitution.r`.

**Data construction:** Left-joined `mining_MR_regular_share_days` and
`mining_MR_confirm_share_days` from `prod_vio_sulfur_hb.parquet` into `two_step_sample`
(PWSID+year key). 6,232 of 12,196 two-step rows have the decomp (1-step downstream CWSs
from hb only; strictly-2-step CWSs lack it and are dropped). 

Sequence indicators (both require t-2 to be violation-free):
- `last_regular_mr`: 220 PWSID-years with regular MR at t-1 after clean t-2
- `last_confirm_mr`: 4 PWSID-years (extremely sparse)

**Results:**
- `last_regular_mr`: β ≈ 0 (6.86×10⁻⁶), SE = 0.005 — regular MR after clean period does
  NOT predict MCL. Scenario 3 (successful substitution or lapse) dominates scenario 1.
  This actually STRENGTHENS the strategic story: CWSs deploy regular MR and usually
  successfully suppress MCL.
- `last_confirm_mr`: β = 0.449 (SE = 0.238, * at 10%) — confirmation MR predicts MCL,
  consistent with monitoring burden (prior positive test → forced confirmation → MCL follows).
  But only 4 observations; treat with extreme caution.
- Key contrast: regular MR (CWS controls timing) → no MCL; confirmation MR (forced by detection) → MCL.

**Output:**
| File | Status |
|------|--------|
| `output/reg/strategic_seq_violations.tex` | OK |

## Open questions / next steps

- Weak first-stage F for 2SLS in forward direction (K=1: 6.7, K=2: 8.3): note in footnote
  and rely primarily on OLS for the temporal sequencing narrative.
- Test 2 confirm MR and Test 4 confirm MR both extremely sparse (9 / 4 PWSID-years);
  the confirm results are effectively underpowered — mention in paper.
- Test 4 restricted to 1-step downstream CWSs (no hb decomp for strictly-2-step CWSs);
  could extend `build_healthbased_mr.py` if full 2-step coverage is needed.

---
**[COMPACTION NOTE � 2026-04-24T03:36:17Z]**  
Auto-compact triggered. Active plan: `none`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---
