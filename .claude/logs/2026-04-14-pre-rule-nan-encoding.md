# Session: 2026-04-14 â€” Pre-rule NaN encoding for VOC, SOC, and SWTR

## Objective
Correct the violation dataset so that VOC, SOC, and Surface/Groundwater Treatment Rule
(SWTR) variables are coded as missing (NaN) for years before those rules were enacted,
rather than zero. Then re-run the 2SLS regression tables and trend figures.

## Rule enactment cutoffs
| Variable group | Rule | First valid year |
|---|---|---|
| voc, voc_* | Phase I VOC Rule (52 FR 25690) | 1989 |
| soc, soc_* | Phase II/V SOC Rules (56 FR 3526, 57 FR 31776) | 1993 |
| surface_ground_water_rule, sgwr_* | SWTR (54 FR 27526) | 1993 |

## Changes Made
- `sdwismatch_pwsid_level_share_yr_in_violation.py`: added NaN block after `fillna(0)`
  (line ~526) that sets all voc*/RULE_CODE_310.0, soc*/RULE_CODE_320.0, and
  surface_ground_water_rule*/RULE_CODE_121/122/123/140 columns to NaN for pre-rule years.
  The _share_days columns (derived from _share * 365 after this block) inherit NaN correctly.
- `didhet.r`: added NA overrides for binary voc, soc, surface_ground_water_rule indicators
  after the binary variable construction block (line ~741).
- `run_main_tables.r`:
  - Per-outcome subsetting: `dset_y <- dset[!is.na(dset[[y]]), ]` so N reflects actual
    non-missing sample for each outcome.
  - Instrument changed from `post95*sulfur_unified` to `post95:sulfur_unified` (interaction
    only) to avoid main-effect collinearity removal in truncated time windows.
  - Each of OLS/RF/IV wrapped in its own tryCatch.
  - Policy: if IV fails, drop ALL columns for that outcome (user preference â€” do not show
    OLS/RF without IV).
- `figures_nonmining_numbervio.r`: new targeted figure script for the two non-mining trend
  figures (avoids running full 2750-line didhet.r).

## Verification Results
- [x] Parquet NaN checks: 6/6 pass (voc_share NaN for 1985-1988, soc/sgwr NaN for 1985-1992)
- [x] Regression output: fixest correctly drops pre-rule years via NA values (LHS) messages
- [x] non_mining_viol figure: VOC lines start 1989, SOC/SWTR lines start 1993
- [x] Downstream-only tables: SOC/SWTR IV fails (only 2 pre-treatment years in 1993-2005
  window, NULL first stage). Per user preference, all columns dropped for those outcomes.

## Design Decisions
| Decision | Rationale |
|---|---|
| NaN in Python pipeline, not R | Fix at the data source so all downstream consumers get correct encoding |
| `post95:sulfur_unified` not `post95*sulfur_unified` | Main effects absorbed by FEs; keeping them causes NULL instrument in short windows |
| Drop all columns if IV fails | User preference: partial results (OLS/RF only) not wanted in table |

## Open Questions / Blockers
- SOC and SWTR are dropped from downstream-only non-mining tables because the 13-year
  window (1993-2005) with only 2 pre-treatment years is insufficient to identify the IV.
  This is a substantive constraint, not a code bug. May be worth noting in paper.
- `surface_ground_water_rule_MCL_share_days` is a constant (zero) â€” no CWS in either
  downstream sample ever had an MCL violation for SWTR. Dropped from all MCL tables.

## Next Steps
- Commit run_main_tables.r changes
- Consider whether to add a note to the paper about SOC/SWTR identification in downstream-only

---
**[COMPACTION NOTE — 2026-04-15T03:26:30Z]**  
Auto-compact triggered. Active plan: `data-driven-nonmining-nan-cutoffs.md`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---

---
**[COMPACTION NOTE — 2026-04-16T01:27:25Z]**  
Auto-compact triggered. Active plan: `data-driven-nonmining-nan-cutoffs.md`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---

---
**[COMPACTION NOTE — 2026-04-16T03:07:58Z]**  
Auto-compact triggered. Active plan: `data-driven-nonmining-nan-cutoffs.md`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---

---
**[COMPACTION NOTE — 2026-04-16T18:42:51Z]**  
Auto-compact triggered. Active plan: `data-driven-nonmining-nan-cutoffs.md`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---
