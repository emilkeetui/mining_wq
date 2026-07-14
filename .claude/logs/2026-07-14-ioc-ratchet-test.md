# Session: 2026-07-14 — IOC ratchet-avoidance test (arsenic, barium, selenium)

## Objective
Extend the nitrate MR-ratchet-avoidance test (`mr_concentration_lag_national.r`) to
arsenic, barium, and selenium, testing whether CWSs avoid monitoring after a reading
near the MCL. National SYR2 sample (1998-2005), all PWSIDs. Implemented per plan
`~/.claude/plans/mr-concentration-lag-ioc-ratchet-test.md`.

## Changes Made
- `code/coal_mining_water_quality/build_mr_concentration_lag_national_ioc.py` (new):
  reads SYR2 .mdb for arsenic/barium/selenium, applies Ravalli + EPA-MDL-fallback
  non-detect imputation, unit normalization, gross-outlier drop, MCL-ratio/near_mcl
  flags (MCLs: As 0.05, Ba 2.0, Se 0.05 mg/L), and same-contaminant MR-violation
  forward/past window matching (vectorized per chemical). Writes
  `clean_data/mr_concentration_lag_national_ioc.parquet`.
- `code/coal_mining_water_quality/mr_concentration_lag_national_ioc.r` (new): pooled
  (chemical FE) and arsenic-only regression tables. Writes
  `output/reg/mr_concentration_lag_national_ioc.tex` and
  `output/reg/mr_concentration_lag_national_arsenic.tex`.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Control = z-scored ratio (VALUE/MCL) within chemical, not raw VALUE | Concentrations aren't comparable across arsenic/barium/selenium; ratio is |
| MR-violation match run separately per chemical (same-contaminant only) | A barium reading must not be matched to an arsenic MR violation |
| near_mcl (50-100% MCL) framed as "ratchet risk," not a sub-MCL trigger | Unlike nitrate's 141.23(d)(2) 50%-of-MCL trigger, IOC quarterly monitoring (141.23(c)(7)) and waiver loss (141.23(c)(2)-(6)) trigger at the MCL itself; arsenic pre-2006 triggers confirmation sampling (old 141.23(m)), not a sustained ratchet |
| Fixed `rename_tex`'s generic "ratio" regex clobbering notes text ("mean ratio of reading to MCL" -> "mean Concen./MCL of reading to MCL") | Reworded notes to avoid the substring collision instead of editing the shared regex |

## Verification Results
- [x] Python build script runs end-to-end, exit 0
- [x] R script runs end-to-end, exit 0
- [x] Parquet exists: 588,837 rows (As 224,035 / Ba 183,118 / Se 181,684)
- [x] near_mcl matches power-check estimate: As 6,179, Ba 448, Se 498 (pooled 7,125)
- [x] Both .tex tables exist, non-zero, correct float/adjustbox nesting, no leftover
      `mr_same_*` variable names or blank dep-var rows

## Results Summary
- **Pooled (As+Ba+Se, chemical FE):** near_mcl coefficient on 1-yr forward MR is
  +0.0029 (not significant, p=0.28); 6-mon forward +0.0012 (n.s.); BUT the past
  (placebo) 6-mon column is significant (+0.0042, p<0.05) and same order of magnitude
  as forward — the pooled result does not cleanly support ratchet avoidance; placebo
  is not clean.
- **Arsenic only:** near_mcl coefficient on forward columns is *negative*
  (-0.0022 1-yr, -0.0011 6-mon), both n.s.; placebo columns near zero/positive. No
  evidence of avoidance in arsenic alone; sign is opposite of the mining/nitrate prior.
- Interpretation: no evidence of a consistent ratchet-avoidance effect for these IOCs
  in the pooled or arsenic-only specs. Contrasts with the nitrate national result
  (separately estimated) — plausibly because the IOC trigger sits at the MCL itself
  (not a sub-MCL band), so the near_mcl band here proxies a weaker/differently-timed
  incentive than nitrate's 50%-of-MCL statutory trigger.

## Open Questions / Blockers
- Whether to also report barium/selenium standalone (both individually underpowered
  per the plan's power check — 448 and 498 near_mcl readings respectively).
- Given the null/wrong-signed results, worth deciding whether this becomes a
  reported robustness/placebo check (IOC trigger differs structurally from nitrate's)
  rather than a positive finding.

## Next Steps
- User review of estimates before deciding whether to include in the dissertation
  chapter as a contrast case to the nitrate ratchet result.
