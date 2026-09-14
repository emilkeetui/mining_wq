# Session: 2026-09-13 — Instrument imputation × step-depth grid (planning)

## Objective
Bring the user up to date on two stalled threads — the downstream-of-intake placebo
("upstream endogeneity test") and the sulfur-instrument standardisation — then write an
implementable plan for a Sonnet model to resolve both jointly.

No analysis code was written or run this session beyond read-only diagnostics. Deliverable
is a plan document.

## Context recovered
- **Placebo thread:** `.claude/logs/2026-08-31-placebo-hop-relaxation-and-purity.md` and
  `2026-08-31-placebo-specification-decisions.md`. Never implemented in the production
  pipeline; `main.tex` contains no `placebo` / `downstream_intake` reference (grepped).
- **Sulfur thread:** the `_sum` variant (coverage-conditional mean) is now the paper's
  headline instrument — only `_ivsum` tables are `\outreg{}`'d in `main.tex`; no legacy
  `_mean` tables remain in the body.
- **Upstream endogeneity test in the paper** is a different exhibit: the
  "Comparability of utilities by upstream production" balance table (`pt_balance_6yr`,
  `\outreg{}` at main.tex:739), which was commented out as of 2026-09-02 and has since been
  re-enabled.

## Changes Made
- `~/.claude/plans/instrument-imputation-and-step-depth-grid.md` (new): the plan.
- `~/.claude/plans/instrument-construction-and-hop-screen-grid.md`: created then **deleted**
  after the user revised scope (dropped the sum instrument, fixed the coverage-drop rule,
  added regulator/enforcement outcomes, capped at 8 steps). Superseded, not archived.
- No project files modified. No `clean_data/` or `output/` writes.

## Verified facts (read-only, this session)
| check | result |
|---|---|
| D1 main sample | 6,232 obs / 340 CWSs |
| CWSs with `sulfur_unified_sum == 0` | 87 (25.6%) — reproduces origin-log finding 11 |
| `num_hucs` per D1 CWS | mean 1.938; 184 CWSs have 1, 156 have ≥2, max 14 |
| `corr(sulfur_unified_mean, sulfur_unified_sum)` on D1 | 0.9838 (both are *means*) |
| `STATE_CODE` present in main + placebo panels | yes → `STATE_CODE^year` FE feasible |
| `SDWA_VIOLATIONS_ENFORCEMENT.parquet` | 306 MB, 14,665,006 rows, 38 cols — twin of the 3.9 GB CSV |

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Flagged that `_sum` is a **misnomer for sulfur** at both aggregation layers | `_mean_nonzero()` (`huc_coal_charac_geom_match.py:261-270`) and mean-over-nonzero (`sdwismatch…py:309-312`) are coverage-conditional *means*, not sums. The user's mean-vs-sum question was therefore a choice between two means; a true sum had never been built. User then dropped the sum from scope. |
| Identified a **second** zero-imputation route | `_unified_pws()`'s `fillna(0)` (`sdwismatch…py:333-337`) *and* a blanket `water_sys.fillna(0)` (line 588). The latter destroys the NaN the comment at line 327 claims to preserve — confirmed empirically: `sulfur_upstream_sum` has 0 NaNs in the panel. Plan therefore requires an explicit integer `n_hucs_covered` column rather than NaN semantics. |
| Imputation contrast run on a **fixed sample** | Since `n_hucs_covered == 0` utilities are dropped in both variants, `sulfur_mean0 ≡ sulfur_meancov × cov_share`, so the contrast isolates coverage variation alone. Plan requires reporting the partially-covered share per `k` — where it is ~0 the variants coincide and a "tie" is mechanical. |
| **Symmetric purity rule** at each depth `k` | User specified step depth but not how purity scales with it. Chose: main arm = mine within `k` upstream and none within `k` downstream; placebo = mirror. Keeps arms disjoint at every `k`, keeps the table one-dimensional in `k`, minimises discretion. Flagged to the user as the one judgment call to confirm or redirect; the alternative (fixed screen, swept exposure) is what the origin log effectively did. |
| Grid outputs to terminal + a results parquet, **not** to `output/reg/` | Exploratory diagnostic; production tables only after a cell is chosen. |
| Outcome caches must be **rebuilt**, not reused | Existing `sdwa_visit_agg_d12` / `sdwa_enf_agg_d12` were built over `union(ids_d12, ids_d1_main)` only — they cover neither the placebo arm nor k≥2. Plan routes the rebuild through the 306 MB parquet twin instead of the 3.9 GB CSV. |
| Pre-registered selection rules, forbidding selection on main-arm significance | Origin log shows the main p-value moving 0.008→0.112 across these choices; choosing on it would be specification search. |

## Verification Results
- [x] Read-only checks run via the venv Python; no writes
- [x] `main.tex` confirmed to contain no placebo/downstream-intake reference
- [x] Plan's reproduction anchors (6,232 / 340 / 87 / F=27.52 / 253 CWSs @ F=12.29,17.20)
      cross-checked against the data or the origin log
- [x] Superseded plan file removed
- [ ] Plan not yet executed — no grid results exist

## Open Questions / Blockers
- **Symmetric vs. decoupled purity screen** — awaiting user confirmation (see Design
  Decisions). Everything else in the plan is specified.
- The **step-3 discontinuity** (origin log finding 9: placebo F jumps 2.28→24.54 at ≤3,
  driven by 26 systems) is still unexplained. Plan gates on characterising it before any
  depth is adopted.
- The three known-bad terminal HUCs (`031002010400`, `031102060605`, `050500030801`, draining
  to OCEAN / CLOSED BASIN) remain unfixed in `minegeomatch.py`. Out of scope here; plan
  treats them as a stop-and-ask if they turn out to drive the step-3 anomaly.
- Expect **no grid cell to reproduce the published F = 27.52** — it depends on retaining the
  87 zero-coverage utilities that the coverage-drop rule removes. Legacy check only.

## Next Steps
1. User confirms or redirects the symmetric purity rule.
2. Hand `~/.claude/plans/instrument-imputation-and-step-depth-grid.md` to a Sonnet
   implementer; branch `instrument-step-grid`.
3. On results: decide the depth + imputation cell, then write production tables as a
   separate task.
