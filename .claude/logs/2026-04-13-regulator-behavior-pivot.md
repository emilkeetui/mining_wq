# Session: 2026-04-13 — Regulator behavior pivot and data profiling

## Objective
Explore SDWA data available on regulator behavior following a pivot in the conference paper focus from health outcomes (MCL violations) to CWS-regulator interactions.

## Changes Made
- `code/coal_mining_water_quality/profile_regulator_data.r`: New script profiling SDWA datasets for regulator behavior variables
- `output/sum/sdwa_regulator_data_inventory.tex`: Four LaTeX tables summarising dataset inventory, site visits, enforcement actions, and recommended outcome variables
- Memory files created/updated (see memory/ folder)

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Both MR and MCL violations remain outcomes | The divergence (MR rises, MCL flat) is the finding to explain, not a nuisance |
| Site visit frequency preferred over eval codes | Eval codes are ~50% missing pre-2000; visit count is always observed |
| Reduced monitoring / outstanding performer dropped | Only 2 and 46 PWSIDs respectively — no power |
| Events/milestones dropped | Almost entirely Lead & Copper Rule milestones (DEEM/DONE), not general regulator behavior |

## Core Research Question (updated)
Why does mining increase MR violations but not MCL violations? Central hypothesis: strategic substitution — CWSs incur MR violations to avoid heavier MCL sanctions, either by re-testing after contaminants clear or by adjusting treatment before required reporting.

## Open Empirical Questions
1. Are MCL sanctions materially larger than MR sanctions? (Check formal enforcement rate by VIOLATION_CATEGORY_CODE)
2. Are MR violations shorter-lived than MCL violations? (Compare days_to_rtc by violation category)
3. How to distinguish genuine from strategic MR violations? (Size heterogeneity, negative MR/MCL correlation within PWSID, sequencing patterns)
4. How do regulators respond differently to MR vs MCL? (Formal enforcement rate, site visit frequency, days to RTC conditional on type)

## Verification Results
- [x] Profile script runs end-to-end (exit 0)
- [x] LaTeX tables written to output/sum/
- [x] Memory files written and MEMORY.md updated

## Key Numbers to Remember
- Sample: 1,507 PWSIDs, 1983–2024
- Site visits (1985–2005): 11,452 rows, 1,181 PWSIDs
- Violations (1985–2005): 108,265 rows; 90% MR, 4% MCL
- Formal enforcement actions: 4,556 (4% of all enforcement)
- Median days to RTC: 119; mean 364

## Next Steps
- Investigate sanction severity by violation type (MCL vs MR) using ENFORCEMENT_ACTION_TYPE_CODE and ENF_ACTION_CATEGORY
- Build PWSID × year panel of regulator behavior outcomes (n_visits, formal_enf, days_to_rtc)
- Develop strategy to identify strategic vs genuine MR violations

---
**[COMPACTION NOTE � 2026-04-13T21:50:23Z]**  
Auto-compact triggered. Active plan: `lively-zooming-swan.md`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---
